#!/usr/bin/env python

import requests_openapi as roa
from opentelemetry import trace
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider, _Span
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
import copy
import datetime
import json
import logging
import os.path
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

def query_traces(start_time_min, start_time_max):
    start_time_min = start_time_min.isoformat() + '.000000000Z'
    start_time_max = start_time_max.isoformat() + '.000000000Z'
    traces = {}
    for service_name in jaeger_client.QueryService_GetServices().json().get('services', []):
        query = {'query.service_name': service_name, 'query.start_time_min': start_time_min, 'query.start_time_max': start_time_max}
        response = jaeger_client.QueryService_FindTraces(**query)
        if response.status_code == 404:
            logging.info(f"No traces found for service {service_name}")
        elif response.status_code == 200:
            logging.info(f"Found traces for service {service_name}")
        else:
            logging.error(f"Response {response.status_code} querying traces: {response.json()}")
        for resource_span in response.json().get('result', {}).get('resourceSpans', []):
            resource = copy.deepcopy(resource_span.get('resource', {}))
            resource['attributes'] = collapse_attributes(resource['attributes'])
            for scope_span in resource_span.get('scopeSpans', []):
                for span in scope_span.get('spans', []):
                    span = copy.deepcopy(span)
                    span['attributes'] = collapse_attributes(span.get('attributes', {}))
                    span['resource'] = resource
                    span['scope'] = scope_span.get('scope', {})
                    trace_id = span.get('traceId')
                    traces.setdefault(trace_id, []).extend([span])
    return traces

def filter_traces(traces, search_attributes):
    new_traces = {}
    for trace_id, spans in traces.items():
        needed_attributes = copy.copy(search_attributes)
        for span in spans:
             for attr, value in list(needed_attributes.items()):
                 if span.get('attributes', {}).get(attr) == value:
                     needed_attributes.pop(attr)
                 elif span.get('resource', {}).get('attributes', {}).get(attr) == value:
                     needed_attributes.pop(attr)
                 elif span.get('scope', {}).get(attr) == value:
                     needed_attributes.pop(attr)
             if not needed_attributes:
                 new_traces[trace_id] = spans
                 break
    return new_traces

def export_traces(traces, first_attributes):
    export_info = {}
    for trace_id, spans in traces.items():
        trace_info = export_info[trace_id] = {}
        for attr in first_attributes:
            for span in spans:
                attr_value = span.get('attributes', {}).get(attr, span.get('resource', {}).get('attributes', {}).get(attr, span.get('scope', {}).get(attr, None)))
                if attr_value != None:
                    trace_info[attr] = attr_value
                    break
        span_counts = trace_info['span_counts'] = {}
        error_counts = trace_info['error_counts'] = {}
        error_messages = trace_info['error_messages'] = []
        for span in spans:
            service_name = span.get('resource', {}).get('attributes', {}).get('service.name', None)
            span_counts[service_name] = span_counts.get(service_name, 0) + 1
            if span.get('attributes', {}).get('error.type', None):
                error_counts[service_name] = error_counts.get(service_name, 0) + 1
                message = span.get('attributes', {}).get('error.message', None)
                if message not in error_messages:
                    error_messages.append(message)
    return export_info

if __name__ == '__main__':
    import argparse
    logging.getLogger().setLevel(logging.INFO)
    parser = argparse.ArgumentParser()
    parser.add_argument('-n', '--dry-run', action='store_true', help="Create the telemetry but don't export them to opentelemetry")
    parser.add_argument('start_time_min', help="The start time to search from")
    parser.add_argument('start_time_max', help="The start time to search to")
    parser.add_argument('attrs', nargs='*', help="Additional attributes in the form attr=value to limit the scope by")
    args = parser.parse_args()
    attributes = {}
    for attr_def in args.attrs:
        if '=' not in attr_def:
            attributes[attr_def] = ''
        else:
            key, value = attr_def.split('=', 1)
            attributes[key] = value
    start_time_min = datetime.datetime.strptime(args.start_time_min, "%Y-%m-%dT%H:%M:%S")
    start_time_max = datetime.datetime.strptime(args.start_time_max, "%Y-%m-%dT%H:%M:%S")
    traces = query_traces(start_time_min, start_time_max)
    logging.info(f"Found {len(traces)} traces between {start_time_min} and {start_time_max}")
    traces = filter_traces(traces, attributes)
    logging.info(f"Filtered {len(traces)} traces between {start_time_min} and {start_time_max}")
    export_info = export_traces(traces, ['http.target'])
    import pprint
    pprint.pprint(export_info)


