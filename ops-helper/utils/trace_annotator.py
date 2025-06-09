#!/usr/bin/env python

import requests_openapi as roa
from opentelemetry import trace
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider, _Span
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

import pprint

def id2int(hex_id):
    return int(hex_id, 16) if hex_id else None

SERVICE_NAME_STR = 'annotator'
ANNOTATOR_NAME = 'brightsun.trace_annotator'

resource = Resource.create(attributes={SERVICE_NAME: SERVICE_NAME_STR})

client = roa.Client().load_spec_from_file("jaeger-api-v3-openapi3.json")
client.set_server(roa.Server(url="http://localhost:16686"))

src_trace_id = "e3d160ec87e67d1262a6cf3326e13c0d"
src_trace = client.QueryService_GetTrace(trace_id=src_trace_id)
src_spans = []
for resource_span in src_trace.json().get('result', {}).get('resourceSpans', []):
    for scope_span in resource_span.get('scopeSpans', []):
        src_spans.extend(scope_span.get('spans', []))
parent_span = src_spans[0]
parent_span_id = parent_span.get('spanId')
pprint.pprint(parent_span)

provider = TracerProvider(resource=resource)
exporter = OTLPSpanExporter(endpoint="http://localhost:4318/v1/traces",)
processor = BatchSpanProcessor(exporter)
provider.add_span_processor(processor)
tracer = provider.get_tracer(ANNOTATOR_NAME)

attributes = {"annotator.phase": "1-query", "annotator.note": "This looks fishy (test)", "annotator.group_id": "test1"}

existing_annotations = [span for span in src_spans if span.get('name') == ANNOTATOR_NAME]

default_trace_flags = trace.span.TraceFlags.get_default()
default_trace_state = trace.span.TraceState.get_default()

parent_context = trace.SpanContext(trace_id=id2int(src_trace_id), span_id=id2int(parent_span_id), is_remote=True,
                                   trace_flags=default_trace_flags, trace_state=default_trace_state)

if existing_annotations:
    # you can't actually add events to an existing annotation span once it has been posted
    this_id = id2int(existing_annotations[0].get('spanId'))
else:
    this_id = tracer.id_generator.generate_span_id()

this_context = trace.SpanContext(trace_id=id2int(src_trace_id), span_id=this_id, is_remote=True,
                                 trace_flags=default_trace_flags, trace_state=default_trace_state)
start_time, end_time = int(parent_span.get('startTimeUnixNano')), int(parent_span.get('endTimeUnixNano'))
span = _Span(name=ANNOTATOR_NAME, context=this_context, parent=parent_context, sampler=tracer.sampler,
             resource=tracer.resource, attributes=attributes, span_processor=tracer.span_processor,
             kind=trace.SpanKind.INTERNAL, links=[], instrumentation_info=tracer.instrumentation_info,
             record_exception=False, set_status_on_exception=False,
             limits=tracer._span_limits, instrumentation_scope=tracer._instrumentation_scope)

# this just sets the start time in the standard implementation
span.start(start_time=start_time, parent_context=parent_context)

span.add_event('comment', {'event_attribute': 'test2'}, timestamp=start_time)

if existing_annotations:
    # this sets the end time and gets the processor to emit
    span.end(end_time=end_time)

else:
    # this doesn't seem to get pushed. But exporting the span actually publishes a new span if one exists...
    # need to figure out how to just add a comment if we want
    from opentelemetry.exporter.otlp.proto.common._internal.trace_encoder import _encode_events
    serialized_events = _encode_events(span.events).SerializePartialToString()
    exporter.export(span.events)


