#!/bin/sh
"exec" """$(dirname $0)/venv/bin/python""" "$0" "$@" # this is a polyglot shell exec which will drop down to the relative virtualenv's python

import argparse
import os
import sys
import yaml
from pathlib import Path

from env_utils import read_env, check_syntax_issues

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

def validate_env_content_structure(data):
    """Validate that the env-content structure matches expected schema"""
    issues = []

    if not isinstance(data, dict):
        issues.append("❌ Root must be a dictionary")
        return issues

    if 'atproto_accounts' not in data:
        issues.append("❌ MISSING: atproto_accounts section")
        return issues

    atproto_accounts = data['atproto_accounts']
    if not isinstance(atproto_accounts, dict):
        issues.append("❌ atproto_accounts must be a dictionary")
        return issues

    if 'follow' not in atproto_accounts:
        issues.append("❌ MISSING: atproto_accounts.follow section")
    else:
        follow = atproto_accounts['follow']
        if not isinstance(follow, dict):
            issues.append("❌ atproto_accounts.follow must be a dictionary")
        else:
            # Validate follow entries
            for account_name, account_data in follow.items():
                if not isinstance(account_data, dict):
                    issues.append(f"❌ atproto_accounts.follow.{account_name} must be a dictionary")
                    continue

                if 'did' not in account_data:
                    issues.append(f"❌ MISSING: atproto_accounts.follow.{account_name}.did")
                elif not account_data['did'] or not account_data['did'].startswith('did:'):
                    issues.append(f"❌ INVALID: atproto_accounts.follow.{account_name}.did must be a valid DID")

    return issues

def main():
    parser = argparse.ArgumentParser(description='Check env-content configuration')
    parser.add_argument('-e', '--env-file', default='.env', help='Environment file (default: .env)')
    parser.add_argument('-c', '--env-content-file', help='Env-content file to check')
    parser.add_argument('-t', '--template-file', default='bluesky-env-content.yml.example',
                        help='Template file (default: bluesky-env-content.yml.example)')
    parser.add_argument('-s', '--silent', action='store_true', help='Silent mode')

    args = parser.parse_args()

    # If no specific env-content file provided, determine from environment
    if not args.env_content_file:
        try:
            # Read environment file to get current configuration
            env_vars = read_env(args.env_file)

            # Check for ENV_CONTENT_FILE override
            if 'ENV_CONTENT_FILE' in env_vars and env_vars['ENV_CONTENT_FILE'].strip():
                args.env_content_file = env_vars['ENV_CONTENT_FILE'].strip('"')
            else:
                # Use convention: .env.NAME -> env-content.NAME.yml
                env_file_path = Path(args.env_file)
                if env_file_path.name == '.env':
                    args.env_content_file = 'env-content.yml'
                elif env_file_path.name.startswith('.env.'):
                    env_name = env_file_path.name[5:]  # Remove '.env.' prefix
                    args.env_content_file = f'env-content.{env_name}.yml'
                else:
                    args.env_content_file = 'env-content.yml'

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
        print(f"Checking env-content configuration:")
        print(f"  Target:   {get_file_info(args.env_content_file)}")
        print(f"  Template: {get_file_info(args.template_file)}")
        print()

    try:
        # Load YAML files
        target_data = load_yaml_file(args.env_content_file)

    except Exception as e:
        if not args.silent:
            print(f"Error loading env-content file: {e}", file=sys.stderr)
        sys.exit(1)

    # Check for syntax issues in the environment file
    env_syntax_issues = []
    if os.path.exists(args.env_file):
        env_syntax_issues = check_syntax_issues(args.env_file)

    # Validate env-content structure
    structure_issues = validate_env_content_structure(target_data)

    # Report results
    all_issues = env_syntax_issues + structure_issues

    if all_issues:
        if not args.silent:
            print("Issues found:")
            for issue in all_issues:
                print(f"  {issue}")
            print()
        sys.exit(1)
    else:
        if not args.silent:
            print("✅ Env-content configuration is valid")
        sys.exit(0)

if __name__ == "__main__":
    main()