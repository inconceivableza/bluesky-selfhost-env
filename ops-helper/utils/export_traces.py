#!/usr/bin/env python

from jaeger_annotation import *
import csv
import copy
import datetime
import json
import logging
import sys

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
             for attr, filter_value in list(needed_attributes.items()):
                 attr_value = get_span_attribute(span, attr)
                 if attr_value == filter_value:
                     needed_attributes.pop(attr)
             if not needed_attributes:
                 new_traces[trace_id] = spans
                 break
    return new_traces

annotator_fields = ['trace_operation_name', 'annotator.batch', 'annotator.label', 'annotator.note']

def export_traces(traces, first_attributes, all_attributes, last_attributes, op_name=None, annotator_batch=None):
    export_info = {}
    for trace_id, spans in traces.items():
        trace_info = export_info[trace_id] = {}
        needed_first_attributes = copy.copy(first_attributes)
        for span in spans:
            for attr in needed_first_attributes[:]:
                attr_value = get_span_attribute(span, attr)
                if attr_value != None:
                    trace_info[attr] = attr_value
                    needed_first_attributes.remove(attr)
            for attr in all_attributes:
                attr_value = get_span_attribute(span, attr)
                if attr_value != None:
                    trace_info.setdefault(attr, []).append(attr_value)
            for attr in last_attributes:
                attr_value = get_span_attribute(span, attr)
                if attr_value != None:
                    trace_info[attr] = attr_value
            service_name = get_span_attribute(span, 'service.name')
            if service_name == SERVICE_NAME_STR:
                span_op_name = get_span_attribute(span, 'operationName')
                if span_op_name == op_name:
                    trace_info['trace_operation_name'] = span_op_name
                    trace_info['annotator.batch'] = get_span_attribute(span, 'annotator.batch', '')
                    trace_info['annotator.label'] = get_span_attribute(span, 'annotator.label', '')
                    trace_info['annotator.note'] = get_span_attribute(span, 'annotator.note', '')
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

def format_csv(f, traces, op_name=None, annotator_batch=None):
    standard_fields = ['trace_id', 'start_time', 'span_counts', 'error_counts', 'error_messages']
    found_attrs = []
    rows = []
    for trace_id, trace in traces.items():
        start_time_str = trace.pop('startTimeUnixNano', '')
        start_time = format_date_csv(parse_unix_nano_time(start_time_str))
        end_time_str = trace.pop('endTimeUnixNano', '')
        end_time = format_date_csv(parse_unix_nano_time(end_time_str))
        trace_link = f'=HYPERLINK("http://localhost:16686/trace/{trace_id}", "{trace_id}")'
        row = {'trace_id': trace_link, 'start_time': start_time, 'trace_operation_name': op_name, 'annotator.batch': annotator_batch}
        span_counts = sorted(trace.get('span_counts', {}).items())
        error_counts = sorted(trace.get('error_counts', {}).items())
        error_messages = sorted(trace.get('error_messages', []))
        row['span_counts'] = ' '.join(f'{service_name}={count}' for (service_name, count) in span_counts)
        row['error_counts'] = ' '.join(f'{service_name}={count}' for (service_name, count) in error_counts)
        row['error_messages'] = '\n'.join(error_messages)
        for attr in trace:
            if attr in standard_fields:
                continue
            if attr not in found_attrs and attr not in annotator_fields:
                found_attrs.append(attr)
            attr_value = trace[attr]
            row[attr] = '\n'.join(attr_value) if isinstance(attr_value, list) else attr_value
        rows.append(row)
    rows.sort(key=lambda d: d.get('start_time'))
    writer = csv.DictWriter(f, standard_fields + found_attrs + annotator_fields)
    writer.writeheader()
    writer.writerows(rows)


if __name__ == '__main__':
    import argparse
    logging.getLogger().setLevel(logging.INFO)
    parser = argparse.ArgumentParser()
    parser.add_argument('-n', '--dry-run', action='store_true', help="Create the telemetry but don't export them to opentelemetry")
    parser.add_argument('--json', dest='output_type', action='store_const', const='json', default='json', help="Output JSON data (defaulit)")
    parser.add_argument('--csv', dest='output_type', action='store_const', const='csv', help="Output CSV data")
    parser.add_argument('-o', '--output-file', help="Output file (default stdout)")
    parser.add_argument('--op-name', help="Trace operation name (to add to csv)")
    parser.add_argument('--batch', help="Trace annotator batch (to add to csv)")
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
    export_info = export_traces(traces, ['startTimeUnixNano'], ['http.target'], ['endTimeUnixNano'])
    with (open(args.output_file, 'w') if args.output_file else sys.stdout) as f:
        if args.output_type == 'json':
            output = json.dump(export_info, f, indent=4)
        elif args.output_type == 'csv':
            output = format_csv(f, export_info, op_name=args.op_name, annotator_batch=args.batch)
            f.write("done\n")


