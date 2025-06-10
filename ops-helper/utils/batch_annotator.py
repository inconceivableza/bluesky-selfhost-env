#!/usr/bin/env python

from jaeger_annotation import *
import csv
import datetime
import logging
import re

LINK_RE = re.compile('=HYPERLINK[(]"(.*)", "(.*)"[)]')

def process_csv_annotations(csv_file, dry_run=False):
    attributes = {'annotator.date': datetime.datetime.now().isoformat()+'000Z'}
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            trace_link = row.get('trace_id')
            trace_m = LINK_RE.match(trace_link)
            trace_id = trace_m.group(2) if trace_m else trace_link
            op_name = row.get('trace_operation_name')
            trace_spans = get_trace_spans(trace_id)
            existing_annotations = filter_annotations(trace_spans)
            annotator_keys = ['annotator.batch', 'annotator.label', 'annotator.note']
            wanted = {key: get_span_attribute(row, key) for key in annotator_keys}
            wanted['operationName'] = op_name
            if not (wanted['annotator.label'] or wanted['annotator.note']):
                # only label what has specific content not added by the export
                continue
            for annotation in existing_annotations:
                existing = {key: get_span_attribute(annotation, key) for key in annotator_keys}
                existing['operationName'] = get_span_attribute(annotation, 'operationName')
                if existing == wanted:
                    logging.info(f"For trace {trace_id}, the existing annotations matched, so not adding")
                    break
            else:
                if existing_annotations:
                    logging.info(f"For trace {trace_id}, none of the {len(existing_annotations)} annotations matched, so adding one")
                    import pprint ; pprint.pprint(existing_annotations)
                    import pdb ; pdb.set_trace()
                add_span_to_trace(trace_id, op_name, wanted, dry_run)


if __name__ == '__main__':
    import argparse
    logging.getLogger().setLevel(logging.INFO)
    parser = argparse.ArgumentParser()
    parser.add_argument('-n', '--dry-run', action='store_true', help="Create the telemetry but don't export them to opentelemetry")
    parser.add_argument('csv_file', help="The CSV file containing traces and annotations")
    args = parser.parse_args()
    process_csv_annotations(args.csv_file, args.dry_run)

