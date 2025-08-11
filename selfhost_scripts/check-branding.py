#!/usr/bin/env python3

import argparse
import os
import sys
import yaml
from pathlib import Path

from env_utils import read_env

def get_file_info(filepath):
    """Get information about a file, including symlink resolution"""
    path = Path(filepath)
    if path.is_symlink():
        target = path.resolve()
        return f"{filepath} -> {target}"
    else:
        return str(path.resolve())

def load_yaml_file(filepath):
    """Load YAML file and return its contents"""
    try:
        with open(filepath, 'r') as f:
            return yaml.safe_load(f)
    except yaml.YAMLError as e:
        raise ValueError(f"Invalid YAML in {filepath}: {e}")
    except Exception as e:
        raise ValueError(f"Error reading {filepath}: {e}")

def compare_yaml_values(example_data, target_data, path="", show_value_changes=False):
    """Recursively compare YAML values and return differences"""
    missing_keys = []
    extra_keys = []
    value_changes = []
    
    if isinstance(example_data, dict) and isinstance(target_data, dict):
        # Check for missing keys in target
        for key in example_data:
            current_path = f"{path}.{key}" if path else key
            if key not in target_data:
                missing_keys.append(f"❌ MISSING: {current_path}")
            else:
                sub_missing, sub_extra, sub_changes = compare_yaml_values(
                    example_data[key], target_data[key], current_path, show_value_changes
                )
                missing_keys.extend(sub_missing)
                extra_keys.extend(sub_extra)
                value_changes.extend(sub_changes)
        
        # Check for extra keys in target
        for key in target_data:
            if key not in example_data:
                current_path = f"{path}.{key}" if path else key
                extra_keys.append(f"ℹ️  EXTRA: {current_path}")
    
    elif isinstance(example_data, list) and isinstance(target_data, list):
        # For lists, we'll just check if they're different
        if show_value_changes and example_data != target_data:
            value_changes.append(f"📝 VALUE CHANGE: {path}. Example: {example_data}, Target: {target_data}")
    
    else:
        # Direct value comparison
        if show_value_changes and example_data != target_data:
            value_changes.append(f"📝 VALUE CHANGE: {path}. Example: {example_data}, Target: {target_data}")
    
    return missing_keys, extra_keys, value_changes

def main():
    parser = argparse.ArgumentParser(description='Compare branding.yml file with example template')
    parser.add_argument('-b', '--branding-file', 
                       help='Branding YAML file to check (default: derived from .env REBRANDING_PARAMS)')
    parser.add_argument('-e', '--env-file', default='.env', 
                       help='Environment file to read (default: .env)')
    parser.add_argument('-t', '--template-file', default='rebranding/repo-rules/branding.yml.example',
                       help='Template file to compare against (default: rebranding/repo-rules/branding.yml.example)')
    parser.add_argument('-v', '--show-value-changes', action='store_true',
                       help='Show variables with different values (default: only show missing keys)')
    parser.add_argument('-s', '--silent', action='store_true',
                       help='Silent mode - no output, just exit codes (0=match, 1=differences)')
    
    args = parser.parse_args()
    
    # If no branding file specified, try to derive it from environment
    if not args.branding_file:
        # Check if .env file exists
        if not os.path.exists(args.env_file):
            if not args.silent:
                print(f"Error: Environment file '{args.env_file}' not found and no branding file specified", file=sys.stderr)
                print("Please specify branding file with -b/--branding-file", file=sys.stderr)
            sys.exit(1)
            
        try:
            # Use env_utils to read the environment file
            env_vars = read_env(args.env_file, interpolate=False)
            
            if 'REBRANDING_PARAMS' not in env_vars:
                if not args.silent:
                    print("Error: Could not find REBRANDING_PARAMS in environment file", file=sys.stderr)
                    print("Please specify branding file with -b/--branding-file", file=sys.stderr)
                sys.exit(1)
            
            # Parse REBRANDING_PARAMS to get the first parameter (directory)
            params_value = env_vars['REBRANDING_PARAMS'].strip('"')
            # Split on whitespace to get the first parameter
            params_parts = params_value.split()
            if not params_parts:
                if not args.silent:
                    print("Error: REBRANDING_PARAMS is empty", file=sys.stderr)
                    print("Please specify branding file with -b/--branding-file", file=sys.stderr)
                sys.exit(1)
            
            branding_dir = params_parts[0]
            args.branding_file = f"{branding_dir}/branding.yml"
                
        except Exception as e:
            if not args.silent:
                print(f"Error reading environment file: {e}", file=sys.stderr)
            sys.exit(1)
    
    # Check if files exist
    if not os.path.exists(args.template_file):
        if not args.silent:
            print(f"Error: Template file '{args.template_file}' not found", file=sys.stderr)
        sys.exit(1)
        
    if not os.path.exists(args.branding_file):
        if not args.silent:
            print(f"Error: Branding file '{args.branding_file}' not found", file=sys.stderr)
        sys.exit(1)
    
    # Show file information (unless silent)
    if not args.silent:
        print(f"Comparing branding files:")
        print(f"  Target:   {get_file_info(args.branding_file)}")
        print(f"  Template: {get_file_info(args.template_file)}")
        print()
    
    try:
        # Load YAML files
        example_data = load_yaml_file(args.template_file)
        target_data = load_yaml_file(args.branding_file)
        
    except Exception as e:
        if not args.silent:
            print(f"Error loading YAML files: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Compare the YAML structures
    missing_keys, extra_keys, value_changes = compare_yaml_values(
        example_data, target_data, show_value_changes=args.show_value_changes
    )
    
    # Track issues and critical errors (missing keys are always critical)
    has_issues = bool(missing_keys or extra_keys or value_changes)
    has_missing_keys = bool(missing_keys)
    
    if not args.silent:
        print("=== BRANDING ANALYSIS ===\n")
        
        # Always show missing keys
        for missing in missing_keys:
            print(missing)
        
        # Show extra keys 
        for extra in extra_keys:
            print(extra)
        
        # Show value changes only if -v flag is used
        if args.show_value_changes:
            for change in value_changes:
                print(change)
        
        if not has_issues:
            print("✅ All branding values match the template!")
    
    # Exit with error code if there are missing keys (critical error)
    if has_missing_keys:
        sys.exit(1)

if __name__ == '__main__':
    main()