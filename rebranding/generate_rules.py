#!/bin/sh
"exec" """$(dirname $0)/venv/bin/python""" "$0" "$@" # this is a shell exec which will drop down to the relative virtualenv's python

import argparse
import json5
import yaml
import pystache
import sys

# Import from selfhost_scripts via requirements.txt link  
from env_utils import read_env

variants = ['development', 'preview', 'testflight']

def variant_files(text):
    results = []
    for line in text.splitlines():
        if '.' in line:
            prefix, ext = line.rsplit('.', 1)
            results.append('\n'.join([line] + [f'{prefix}.{variant}.{ext}' for variant in variants]))
        else:
            results.append(line)
    return '\n'.join(results) + '\n'

def main():
    parser = argparse.ArgumentParser(description='Generate YAML files from Mustache templates using config variables')
    parser.add_argument('-c', '--config', required=True, help='JSON5 config file with variables')
    parser.add_argument('-e', '--env', action='append', default=[], help='Environment file (can specify multiple)')
    parser.add_argument('input_file', help='Input Mustache template file')
    parser.add_argument('output_file', help='Output YAML file')
    
    args = parser.parse_args()
    
    try:
        # Load config variables from YAML file
        with open(args.config, 'r') as f:
            config_vars = json5.load(f)
        
        # Load environment variables from env files
        env_vars = {}
        for env_file in args.env:
            env_vars.update(read_env(env_file, interpolate=True))
        
        # Add env variables under 'env' key
        if env_vars:
            config_vars['env'] = env_vars
        config_vars['variant_files'] = variant_files
        
        # Read the Mustache template
        with open(args.input_file, 'r') as f:
            template = f.read()
        
        # Render the template with config variables
        renderer = pystache.Renderer(escape=lambda u: u)
        rendered_content = renderer.render(template, config_vars)
        
        # Write the output YAML file
        with open(args.output_file, 'w') as f:
            f.write(rendered_content)
        
        print(f"Successfully generated {args.output_file} from {args.input_file} using config {args.config}")
        
    except FileNotFoundError as e:
        print(f"Error: File not found - {e}", file=sys.stderr)
        sys.exit(1)
    except json5.JSONDecodeError as e:
        print(f"Error: Invalid YAML in config file - {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
