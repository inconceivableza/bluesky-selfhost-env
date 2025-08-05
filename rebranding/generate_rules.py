#!/usr/bin/env python3

import argparse
import yaml
import pystache
import sys
from env_utils import read_env

def main():
    parser = argparse.ArgumentParser(description='Generate YAML files from Mustache templates using config variables')
    parser.add_argument('-c', '--config', required=True, help='YAML config file with variables')
    parser.add_argument('-e', '--env', action='append', default=[], help='Environment file (can specify multiple)')
    parser.add_argument('input_file', help='Input Mustache template file')
    parser.add_argument('output_file', help='Output YAML file')
    
    args = parser.parse_args()
    
    try:
        # Load config variables from YAML file
        with open(args.config, 'r') as f:
            config_vars = yaml.safe_load(f)
        
        # Load environment variables from env files
        env_vars = {}
        for env_file in args.env:
            env_vars.update(read_env(env_file, interpolate=True))
        
        # Add env variables under 'env' key
        if env_vars:
            config_vars['env'] = env_vars
        
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
    except yaml.YAMLError as e:
        print(f"Error: Invalid YAML in config file - {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()