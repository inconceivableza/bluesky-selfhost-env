#!/usr/bin/env python

import requests_openapi as roa
from opentelemetry import trace
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider, _Span
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
import copy
import logging
import pprint

def id2int(hex_id):
    return int(hex_id, 16) if hex_id else None

SERVICE_NAME_STR = 'annotator'
ANNOTATOR_NAME = 'brightsun.trace_annotator'

def open_jaeger_client():
    client = roa.Client().load_spec_from_file("jaeger-api-v3-openapi3.json")
    client.set_server(roa.Server(url="http://localhost:16686"))
    return client

def setup_otlp_client():
    resource = Resource.create(attributes={SERVICE_NAME: SERVICE_NAME_STR})
    provider = TracerProvider(resource=resource)
    exporter = OTLPSpanExporter(endpoint="http://localhost:4318/v1/traces",)
    processor = BatchSpanProcessor(exporter)
    provider.add_span_processor(processor)
    tracer = provider.get_tracer(ANNOTATOR_NAME)
    return tracer, exporter

jaeger_client = open_jaeger_client()

tracer, exporter = setup_otlp_client()

def collapse_attributes(attributes):
    new_attributes = {}
    for attrdict in attributes:
        value = attrdict['value']
        if isinstance(value, dict) and 'stringValue' in value:
            value = value['stringValue']
        elif isinstance(value, dict) and 'intValue' in value:
            value = value['intValue']
        elif isinstance(value, dict) and 'doubleValue' in value:
            value = value['doubleValue']
        elif isinstance(value, dict) and 'boolValue' in value:
            value = value['boolValue']
        new_attributes[attrdict['key']] = value
    return new_attributes

def get_trace_spans(src_trace_id):
    src_trace = jaeger_client.QueryService_GetTrace(trace_id=src_trace_id)
    src_spans = []
    for resource_span in src_trace.json().get('result', {}).get('resourceSpans', []):
        resource = copy.deepcopy(resource_span.get('resource', {}))
        resource['attributes'] = collapse_attributes(resource['attributes'])
        for scope_span in resource_span.get('scopeSpans', []):
            for span in scope_span.get('spans', []):
                span = copy.deepcopy(span)
                span['attributes'] = collapse_attributes(span['attributes'])
                span['resource'] = resource
                span['scope'] = scope_span.get('scope', {})
                src_spans.append(span)
    return src_spans

default_trace_flags = trace.span.TraceFlags.get_default()
default_trace_state = trace.span.TraceState.get_default()

def make_span_context(trace_id, span_id):
    return trace.SpanContext(trace_id=trace_id, span_id=span_id, is_remote=True, trace_flags=default_trace_flags, trace_state=default_trace_state)

def add_span_to_trace(src_trace_id, name, attributes):
    src_spans = get_trace_spans(src_trace_id)
    parent_span = src_spans[0]
    parent_span_id = parent_span.get('spanId')
    existing_annotations = [span for span in src_spans if span.get('resource', {}).get('attributes', {}).get('service.name', None) == SERVICE_NAME_STR]
    if existing_annotations:
        logging.info(f"Trace {src_trace_id} already has {len(existing_annotations)} annotations")
    src_trace_id_int = id2int(src_trace_id)
    this_id = tracer.id_generator.generate_span_id()
    parent_context = make_span_context(src_trace_id_int, id2int(parent_span_id))
    this_context = make_span_context(src_trace_id_int, this_id)
    start_time, end_time = int(parent_span.get('startTimeUnixNano')), int(parent_span.get('endTimeUnixNano'))
    span = _Span(name=name, context=this_context, parent=parent_context, sampler=tracer.sampler,
                 resource=tracer.resource, attributes=attributes, span_processor=tracer.span_processor,
                 kind=trace.SpanKind.INTERNAL, links=[], instrumentation_info=tracer.instrumentation_info,
                 record_exception=False, set_status_on_exception=False,
                 limits=tracer._span_limits, instrumentation_scope=tracer._instrumentation_scope)
    span.start(start_time=start_time, parent_context=parent_context)
    span.add_event('comment', {'event_attribute': 'test2'}, timestamp=start_time)
    span.end(end_time=end_time)
    pprint.pprint(span)
    exporter.export([span])

if __name__ == '__main__':
    src_trace_id = "e3d160ec87e67d1262a6cf3326e13c0d"
    attributes = {"annotator.phase": "1-query", "annotator.note": "This looks fishy (test)", "annotator.group_id": "test2"}
    add_span_to_trace(src_trace_id, "annotation.test", attributes)

