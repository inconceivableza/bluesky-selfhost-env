#!/bin/sh
"exec" """$(dirname $0)/venv/bin/python""" "$0" "$@" # this is a polyglot shell exec which will drop down to the relative virtualenv's python

import argparse
import os
import sys
import json5
from pathlib import Path

from env_utils import base_dir, check_syntax_issues, read_env

def get_file_info(filepath):
    """Get information about a file, including symlink resolution"""
    path = Path(filepath)
    if path.is_symlink():
        target = path.resolve()
        return f"{filepath} -> {target}"
    else:
        return str(path.resolve())

def load_json5_file(filepath):
    """Load JSON5 file and return its contents"""
    try:
        with open(filepath, 'r') as f:
            return json5.load(f)
    except json5.JSON5DecodeError as e:
        raise ValueError(f"Invalid JSON5 in {filepath}: {e}")
    except Exception as e:
        raise ValueError(f"Error reading {filepath}: {e}")

def compare_json5_values(example_data, target_data, path="", show_value_changes=False):
    """Recursively compare JSON5 values and return differences"""
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
                sub_missing, sub_extra, sub_changes = compare_json5_values(
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
    parser = argparse.ArgumentParser(description='Compare env-content.json file with example template')
    parser.add_argument('-c', '--env-content-file',
                       help='Env-content JSON5 file to check (default: derived from .env ENV_CONTENT_FILE)')
    parser.add_argument('-d', '--env-content-dir', default=base_dir / 'repos' / 'social-app' / 'submodules' / 'atproto', type=Path,
                       help='Directory to locate Env-content files to check (default: ./repos/social-app/submodules/atproto/')
    parser.add_argument('-e', '--env-file', default='.env',
                       help='Environment file to read (default: .env)')
    parser.add_argument('-t', '--template-file', default='bluesky-env-content.example.json5',
                       help='Template file to compare against (default: bluesky-env-content.example.json5)')
    parser.add_argument('-v', '--show-value-changes', action='store_true',
                       help='Show variables with different values (default: only show missing keys)')
    parser.add_argument('-s', '--silent', action='store_true',
                       help='Silent mode - no output, just exit codes (0=match, 1=differences)')

    args = parser.parse_args()

    # If no env-content file specified, try to derive it from environment
    if not args.env_content_file:
        # Check if .env file exists
        if not os.path.exists(args.env_file):
            if not args.silent:
                print(f"Error: Environment file '{args.env_file}' not found and no env-content file specified", file=sys.stderr)
                print("Please specify env-content file with -c/--env-content-file", file=sys.stderr)
            sys.exit(1)

        try:
            # Use env_utils to read the environment file
            env_vars = read_env(args.env_file, interpolate=False)

            # Check for ENV_CONTENT_FILE override
            if 'ENV_CONTENT_FILE' in env_vars and env_vars['ENV_CONTENT_FILE'].strip():
                args.env_content_file = env_vars['ENV_CONTENT_FILE'].strip('"')
            else:
                # Use convention: .env.NAME -> env-content.NAME.json
                env_file_path = Path(args.env_file)
                if env_file_path.name == '.env':
                    env_content_file = 'env-content.json'
                elif env_file_path.name.startswith('.env.'):
                    env_name = env_file_path.name[5:]  # Remove '.env.' prefix
                    env_content_file = f'env-content.{env_name}.json'
                else:
                    env_content_file = 'env-content.json'
                args.env_content_file = args.env_content_dir / env_content_file

        except Exception as e:
            if not args.silent:
                print(f"Error reading environment file: {e}", file=sys.stderr)
            sys.exit(1)

    # Check if files exist
    if not os.path.exists(args.template_file):
        if not args.silent:
            print(f"Error: Template file '{args.template_file}' not found", file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(args.env_content_file):
        if not args.silent:
            print(f"Error: Env-content file '{args.env_content_file}' not found", file=sys.stderr)
            print(f"Copy {args.template_file} to {args.env_content_file} and customize as needed", file=sys.stderr)
        sys.exit(1)

    # Show file information (unless silent)
    if not args.silent:
        print(f"Comparing env-content files:")
        print(f"  Target:   {get_file_info(args.env_content_file)}")
        print(f"  Template: {get_file_info(args.template_file)}")
        print()

    try:
        # Load JSON5 files
        example_data = load_json5_file(args.template_file)
        target_data = load_json5_file(args.env_content_file)

    except Exception as e:
        if not args.silent:
            print(f"Error loading JSON5 files: {e}", file=sys.stderr)
        sys.exit(1)

    # Check for syntax issues in the environment file if we read it
    env_syntax_issues = []
    if not args.env_content_file and os.path.exists(args.env_file):
        env_syntax_issues = check_syntax_issues(args.env_file)

    # Compare the JSON5 structures
    missing_keys, extra_keys, value_changes = compare_json5_values(
        example_data, target_data, show_value_changes=args.show_value_changes
    )

    # Track issues and critical errors (missing keys are always critical)
    has_issues = bool(missing_keys or extra_keys or value_changes)
    has_missing_keys = bool(missing_keys)
    has_syntax_issues = len(env_syntax_issues) > 0

    if not args.silent:
        print("=== ENV-CONTENT ANALYSIS ===\n")

        # Report syntax issues in env file first
        if env_syntax_issues:
            print("Environment file syntax issues:")
            for issue in env_syntax_issues:
                print(f"🚨 SYNTAX: {issue}")
            print()  # Add blank line after syntax issues

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

        if not has_issues and not has_syntax_issues:
            print("✅ All env-content values match the template!")

    # Exit with error code if there are missing keys or syntax issues (critical errors)
    if has_missing_keys or has_syntax_issues:
        if not args.silent:
            error_parts = []
            if has_syntax_issues:
                error_parts.append("syntax errors")
            if has_missing_keys:
                error_parts.append("missing keys")

            error_msg = " and ".join(error_parts)
            print(f"❌ Error: there are {error_msg} in this configuration")
        sys.exit(1)

    # Exit with informational message if there are only extra keys (not critical)
    if has_issues and not has_missing_keys:
        if not args.silent:
            print("ℹ️  Note: There are extra keys in the configuration (not critical)")
        sys.exit(0)

    sys.exit(0)

if __name__ == "__main__":
    main()
