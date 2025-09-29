#!/bin/sh
"exec" """$(dirname $0)/venv/bin/python""" "$0" "$@" # this is a polyglot shell exec which will drop down to the relative virtualenv's python

"""
Generate env-content JSON files for bsky appview from YAML configurations.

This script reads env-content YAML files and converts them to JSON format
for inclusion in the bsky appview Docker image.
"""

import argparse
import json
import sys
import yaml
from pathlib import Path

base_dir = Path(__file__).parent.parent

from env_utils import get_existing_profile_names, validate_profile_name

def load_yaml_file(filepath):
    """Load YAML file and return its contents"""
    try:
        with open(filepath, 'r') as f:
            return yaml.safe_load(f)
    except yaml.YAMLError as e:
        raise ValueError(f"Invalid YAML in {filepath}: {e}")
    except Exception as e:
        raise ValueError(f"Error reading {filepath}: {e}")

def get_env_content_input_path(profile):
    """Get the input path for env-content YAML file based on profile."""
    base_path = base_dir

    if profile is None:
        return base_path / "env-content.yml"
    else:
        return base_path / f"env-content.{profile}.yml"

def get_env_content_output_path(profile, args):
    """Get the output path for env-content JSON file based on profile."""
    base_path = base_dir / Path("repos/atproto/services/bsky")
    if args.output:
        if args.output.endswith('/'):
            base_path = base_dir / Path(args.output)
        else:
            return base_path / Path(args.output)

    if profile is None:
        return base_path / "env-content.json"
    else:
        return base_path / f"env-content.{profile}.json"

def validate_env_content_structure(data):
    """Validate that the env-content structure matches expected schema"""
    if not isinstance(data, dict):
        raise ValueError("Root must be a dictionary")

    if 'atproto_accounts' not in data:
        raise ValueError("Missing required 'atproto_accounts' section")

    atproto_accounts = data['atproto_accounts']
    if not isinstance(atproto_accounts, dict):
        raise ValueError("'atproto_accounts' must be a dictionary")

    if 'follow' not in atproto_accounts:
        raise ValueError("Missing required 'atproto_accounts.follow' section")

    follow = atproto_accounts['follow']
    if not isinstance(follow, dict):
        raise ValueError("'atproto_accounts.follow' must be a dictionary")

    # Validate follow entries
    for account_name, account_data in follow.items():
        if not isinstance(account_data, dict):
            raise ValueError(f"'atproto_accounts.follow.{account_name}' must be a dictionary")

        if 'did' not in account_data:
            raise ValueError(f"Missing required 'atproto_accounts.follow.{account_name}.did'")

        did = account_data['did']
        if not did or not str(did).startswith('did:'):
            raise ValueError(f"'atproto_accounts.follow.{account_name}.did' must be a valid DID")

def generate_env_content_for_profile(profile, args):
    """Generate env-content JSON file for a specific profile."""
    # Get input and output paths
    input_path = get_env_content_input_path(profile)
    output_path = get_env_content_output_path(profile, args)

    if not input_path.exists():
        if not args.quiet:
            print(f"Warning: env-content file {input_path} not found, skipping")
        return True

    try:
        # Load YAML data
        env_content_data = load_yaml_file(input_path)

        # Validate structure
        validate_env_content_structure(env_content_data)

        # Ensure output directory exists
        output_path.parent.mkdir(parents=True, exist_ok=True)

        # Write JSON file
        with open(output_path, 'w') as f:
            json.dump(env_content_data, f, indent=2)

        if not args.quiet:
            print(f"Generated {output_path} from {input_path}")

        return True

    except Exception as e:
        print(f"Error generating env-content for profile '{profile}': {e}", file=sys.stderr)
        return False

def main():
    parser = argparse.ArgumentParser(description='Generate bsky appview env-content JSON files from YAML')
    parser.add_argument('-p', '--profile', help='Profile name to generate (default: all profiles)')
    parser.add_argument('-o', '--output', help='Output directory or specific file path')
    parser.add_argument('-q', '--quiet', action='store_true', help='Suppress output messages')

    args = parser.parse_args()

    # Validate profile if provided
    if args.profile:
        if not validate_profile_name(args.profile):
            print(f"Error: Invalid profile name '{args.profile}'", file=sys.stderr)
            sys.exit(1)

    success = True

    if args.profile:
        # Generate for specific profile
        success = generate_env_content_for_profile(args.profile, args)
    else:
        # Generate for all profiles (including default)
        profiles = [None] + get_existing_profile_names()

        for profile in profiles:
            if not generate_env_content_for_profile(profile, args):
                success = False

    if not success:
        sys.exit(1)

    if not args.quiet:
        print("✅ Env-content JSON generation completed")

if __name__ == "__main__":
    main()