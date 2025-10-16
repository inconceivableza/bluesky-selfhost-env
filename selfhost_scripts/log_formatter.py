#!/bin/sh
"exec" """$(dirname "$0")/venv/bin/python""" "$0" "$@" # this is a polyglot shell exec which will drop down to the relative virtualenv's python

import json, sys, argparse
import datetime
import rich

status_line_varnames = ['time', 'ts', 'level', 'pid', 'remote_ip', 'host', 'hostname', 'name', 'status', 'req_method', 'req_url', 'res_statusCode', 'msg']
req_extract_vars = ['method', 'url', 'query', 'params']
res_extract_vars = ['statusCode']

def adjust_vars(record):
    if 'req' in record and 'res' in record:
        req, res = record.pop('req'), record.pop('res')
        for req_key in req_extract_vars:
            if req_key in req:
                record[f'req_{req_key}'] = req.pop(req_key)
        record['req'] = json.dumps(req)
        for res_key in res_extract_vars:
            if res_key in res:
                record[f'res_{res_key}'] = res.pop(res_key)
        record['res'] = json.dumps(res)
    return record

def main(args):
    for line in sys.stdin:
        if not '|' in line and not args.no_json_prefix:
            sys.stdout.write(line)
            continue
        if args.no_json_prefix:
            service_prefix, log_json = args.default_service_prefix, line
        else:
            service_prefix, log_json = line.split('|',1)
            service_name = service_prefix.strip()
        try:
            log_obj = json.loads(log_json)
        except Exception as e:
            rich.print(f"[bold green]{service_prefix}[/bold green]|", end='')
            print(log_json.rstrip())
            continue
        log_obj = adjust_vars(log_obj)
        status_vars = {}
        for varname in status_line_varnames:
            if varname in log_obj:
                value = log_obj.pop(varname)
                if varname == 'time' and type(value) == int:
                    value = datetime.datetime.fromtimestamp(value/1000.)
                elif varname == 'ts' and type(value) == float:
                    value = datetime.datetime.fromtimestamp(value)
                status_vars[varname] = value
        status_line = ' '.join([f"{varname}={status_vars[varname]}" for varname in status_line_varnames if varname in status_vars])
        rich.print(f"[bold green]{service_prefix}[/bold green]|", status_line, log_obj)

if __name__ == '__main__':
   parser = argparse.ArgumentParser()
   parser.add_argument('--no-json-prefix', action='store_true', help='Read JSON from each line rather than the service prefix that docker produces')
   parser.add_argument('--default-service-prefix', default='stdout', help='Use this as the service prefix for output when none is supplied')
   args = parser.parse_args()
   try:
       main(args)
   except KeyboardInterrupt:
       rich.print("[bold blue]Goodbye[/bold blue]")
       sys.exit()

