#!/usr/bin/env python

import requests_openapi as roa
from opentelemetry import trace
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider, _Span
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
import copy
import datetime
import json
import logging
import os.path

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

short_trace_id_map = {}

SHORT_TRACE_ID_FILENAME = 'jaeger-short-trace-ids.json'
if os.path.exists(SHORT_TRACE_ID_FILENAME):
    with open(SHORT_TRACE_ID_FILENAME, 'r') as f:
        short_trace_id_map.update(json.load(f))

def find_trace_id(short_trace_id, days=7):
    if short_trace_id in short_trace_id_map:
        return short_trace_id_map[short_trace_id][0]
    start_time_min = (datetime.datetime.now() - datetime.timedelta(days=days)).isoformat() + '000Z'
    start_time_max = (datetime.datetime.now() + datetime.timedelta(days=0)).isoformat() + '000Z'
    found_trace_id = None
    for service_name in jaeger_client.QueryService_GetServices().json().get('services', []):
        query = {'query.service_name': service_name, 'query.start_time_min': start_time_min, 'query.start_time_max': start_time_max}
        # this is wasteful and returns the full traces
        traces = jaeger_client.QueryService_FindTraces(**query).json()
        for resource_span in traces.get('result', {}).get('resourceSpans', []):
            for scope_span in resource_span.get('scopeSpans', []):
                for span in scope_span.get('spans', []):
                    trace_id = span.get('traceId')
                    short_trace_id_map.setdefault(trace_id[:7], []).extend([trace_id])
                    if trace_id[:7] == short_trace_id:
                        found_trace_id = trace_id
    with open(SHORT_TRACE_ID_FILENAME, 'w') as f:
        json.dump(short_trace_id_map, f)
    return found_trace_id

def parse_unix_nano_time(ds):
    return datetime.datetime.fromtimestamp(int(ds)/1000000000) if ds else None

def format_date_csv(d):
    return d.strftime('%Y-%m-%d %H:%M:%S.%f') if d is not None else ''

