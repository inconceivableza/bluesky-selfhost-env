#!/bin/sh
"exec" """$(dirname $0)/venv/bin/python""" "$0" "$@" # this is a polyglot shell exec which will drop down to the relative virtualenv's python

"""
Generate env-content JSON files for bsky appview from JSON5 configurations.

This script reads env-content JSON files and converts them to JSON format
for inclusion in the bsky appview Docker image.
"""

import argparse
import json
import sys
import json5
from pathlib import Path

base_dir = Path(__file__).parent.parent

from env_utils import get_existing_profile_names, validate_profile_name

def load_json5_file(filepath):
    """Load JSON5 file and return its contents"""
    try:
        with open(filepath, 'r') as f:
            return json5.load(f)
    except json5.JSON5DecodeError as e:
        raise ValueError(f"Invalid JSON5 in {filepath}: {e}")
    except Exception as e:
        raise ValueError(f"Error reading {filepath}: {e}")

def get_env_content_input_path(profile):
    """Get the input path for env-content JSON5 file based on profile."""
    base_path = base_dir / "repos" / "atproto"

    if profile is None:
        return base_path / "env-content.json"
    else:
        return base_path / f"env-content.{profile}.json"

def get_env_content_output_paths(profile, args):
    """Get the output path for env-content JSON file based on profile."""
    base_path = base_dir
    for output in args.output or [base_dir / Path("repos/atproto/services/bsky")]:
        if output.endswith('/'):
            base_path = base_dir / Path(output)
        else:
            yield base_path / Path(output)
        if profile is None:
            yield base_path / "env-content.json"
        else:
            yield base_path / f"env-content.{profile}.json"

def generate_env_content_for_profile(profile, args):
    """Generate env-content JSON file for a specific profile."""
    # Get input and output paths
    input_path = get_env_content_input_path(profile)
    output_paths = list(get_env_content_output_paths(profile, args))

    if not input_path.exists():
        if not args.silent:
            print(f"Warning: env-content file {input_path} not found, skipping")
        return True

    try:
        # Load JSON5 data
        env_content_data = load_json5_file(input_path)

        for output_path in output_paths:
            if args.dry_run:
                if not args.silent:
                    print(f"Would have written to {output_path}")
                continue

            # Ensure output directory exists
            output_path.parent.mkdir(parents=True, exist_ok=True)

            # Write JSON file
            with open(output_path, 'w') as f:
                json.dump(env_content_data, f, indent=2)

            if not args.silent:
                print(f"Generated {output_path} from {input_path}")

        return True

    except Exception as e:
        print(f"Error generating env-content for profile '{profile}': {e}", file=sys.stderr)
        return False
        if args.dry_run:
            print("🔍 DRY RUN MODE - No files will be written")

def main():
    parser = argparse.ArgumentParser(description='Generate bsky appview env-content JSON files from JSON5')
    parser.add_argument('-s', '--silent', action='store_true',
                       help='Silent mode - no output except errors')
    parser.add_argument('--dry-run', action='store_true',
                       help='Show what would be generated without writing files')

    parser.add_argument(
        '-p', '--profile',
        action='append',
        dest='profiles',
        default=[],
        help='Target profile for .env.{profile} (allows [a-zA-Z0-9_.+-] characters, can be used multiple times)'
    )
    parser.add_argument(
        '-D', '--default',
        action='append_const',
        const='default',
        dest='profiles',
        help='Shortcut for --profile default which targets the main .env file'
    )
    parser.add_argument(
        '-P', '--prod',
        action='append_const',
        const='production',
        dest='profiles',
        help='Shortcut for --profile production'
    )
    parser.add_argument(
        '-T', '--test',
        action='append_const',
        const='test',
        dest='profiles',
        help='Shortcut for --profile test'
    )
    parser.add_argument(
        '-a', '--all-profiles',
        action='store_true',
        help='Generate for all existing .env* files'
    )
    parser.add_argument(
        '-o', '--output', default=[], action='append',
        help='Set a filename or directory prefix (if ending with /) to output (relative to base selfh-host directory; defaults to repos/atproto/services/bsky and .env or .env.$profile) - multiple supported',
    )

    args = parser.parse_args()

    # Handle profile selection
    profiles = [None if p == 'default' else p for p in args.profiles] or []
    default_profiles = [None, "production", "test"]
    
    if args.all_profiles:
        # Add all existing profiles to the list
        existing_profiles = get_existing_profile_names()
        for profile in existing_profiles:
            if profile not in profiles:
                profiles.append(profile)
        for profile in default_profiles:
            if profile not in profiles:
                profiles.append(profile)
    
    # Validate all profiles
    for profile in profiles:
        if profile and not validate_profile_name(profile):
            parser.error(f"Profile name {profile} is not valid")
    
    # If no profiles specified, default to None (which means .env)
    if not profiles:
        profiles = [None]
    
    if not args.silent:
        print(f"🔧 Processing {len(profiles)} profile(s): {', '.join(str(p) or 'default' for p in profiles)}")
        if args.dry_run:
            print("🔍 DRY RUN MODE - No files will be written")
        print()
    
    success = True

    for profile in profiles:
        # Generate for specific profile
        success = generate_env_content_for_profile(profile, args)

    if not success:
        sys.exit(1)

    if not args.silent:
        print("✅ Env-content JSON generation completed")

if __name__ == "__main__":
    main()
