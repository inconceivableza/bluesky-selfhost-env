#!/usr/bin/env python

from jaeger_annotation import *
import datetime
import logging

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

