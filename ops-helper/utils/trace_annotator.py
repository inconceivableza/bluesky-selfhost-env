#!/usr/bin/env python

from jaeger_annotation import *
from opentelemetry.sdk.trace import _Span
import datetime
import logging

def add_span_to_trace(src_trace_id, name, attributes, dry_run=False):
    if len(src_trace_id) < 32:
        short_trace_id = src_trace_id
        logging.info(f"Searching for full trace_id for {src_trace_id}")
        src_trace_id = find_trace_id(short_trace_id, days=7)
        if src_trace_id:
            logging.info(f"Found {src_trace_id} for {short_trace_id}")
        else:
            raise ValueError("Could not find full trace id for {short_trace_id} (searched 7 days)")
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
    # span.add_event('comment', {'event_attribute': 'test2'}, timestamp=start_time)
    span.end(end_time=end_time)
    if dry_run:
        logging.info("Span created, not exporting")
    else:
        logging.info("Exporting span with id {this_id:x}")
        exporter.export([span])

if __name__ == '__main__':
    import argparse
    logging.getLogger().setLevel(logging.INFO)
    parser = argparse.ArgumentParser()
    parser.add_argument('-n', '--dry-run', action='store_true', help="Create the telemetry but don't export them to opentelemetry")
    parser.add_argument('trace_id', help="The hex ID of the trace to be annotated")
    parser.add_argument('operation_name', help="The name to attach to this span (appears in jaeger next to annotator)")
    parser.add_argument('attrs', nargs='*', help="Additional attributes in the form attr=value")
    args = parser.parse_args()
    attributes = {'annotator.date': datetime.datetime.now().isoformat()+'000Z'}
    for attr_def in args.attrs:
        if '=' not in attr_def:
            attributes[attr_def] = ''
        else:
            key, value = attr_def.split('=', 1)
            attributes[key] = value
    add_span_to_trace(args.trace_id, args.operation_name, attributes, dry_run=args.dry_run)

