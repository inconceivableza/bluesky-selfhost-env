#!/bin/sh
"exec" """$(dirname $0)/venv/bin/python""" "$0" "$@" # this is a polyglot shell exec which will drop down to the relative virtualenv's python

"""
Generate environment files for social-app from profile configurations.

This script reads environment variables from profile files and generates
corresponding .env files for the social-app Docker image using a mustache template.
"""

import argparse
import subprocess
import sys
from pathlib import Path

base_dir = Path(__file__).parent.parent

from env_utils import get_existing_profile_names, read_env, validate_profile_name

def render_mustache_template(template_content, variables):
    """Simple mustache template renderer for basic variable substitution."""
    result = template_content
    
    # Handle basic {{variable}} substitutions
    for key, value in variables.items():
        pattern = f"{{{{{key}}}}}"
        result = result.replace(pattern, str(value))
    
    return result

def get_social_env_output_path(profile, args):
    """Get the output path for social-app env file based on profile."""
    base_path = base_dir / Path("repos/social-app")
    if args.output:
        if args.output.endswith('/'):
            base_path = base_dir / Path(args.output)
        else:
            return base_path / Path(args.output) # will compute as relative unless args.output is absolute
    
    if profile is None:
        return base_path / ".env"
    else:
        return base_path / f".env.{profile}"

def generate_social_env_for_profile(profile, template_content, args):
    """Generate social-app environment file for a specific profile."""
    # Read environment variables from profile file
    env_file_path = base_dir / Path(f".env.{profile}" if profile else ".env")
    
    if not env_file_path.exists():
        print(f"Warning: Environment file {env_file_path} not found for profile {profile or 'default'}", file=sys.stderr)
        return False
    
    if not args.silent:
        print(f"📁 Processing profile: {profile or 'default'} ({env_file_path})")
    
    try:
        # Read environment with interpolation to resolve variables
        env_vars = read_env(str(env_file_path), interpolate=True)
    except Exception as e:
        print(f"Error reading environment file {env_file_path}: {e}", file=sys.stderr)
        return False
    
    # Render template
    rendered_content = render_mustache_template(template_content, env_vars)
    
    # Determine output path
    output_path = get_social_env_output_path(profile, args)
    
    if args.dry_run:
        if not args.silent:
            print(f"🔍 Would generate: {output_path}")
            print("Content:")
            print(rendered_content)
            print("-" * 40)
        return True
    
    # Ensure output directory exists
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Write output file
    try:
        with open(output_path, 'w') as f:
            f.write(rendered_content)
        
        if not args.silent:
            print(f"✅ Generated: {output_path}")
        
        return True
        
    except Exception as e:
        print(f"Error writing output file {output_path}: {e}", file=sys.stderr)
        return False

def generate_branding_file(args):
    env_file_path = base_dir / Path(f".env.production")
    if not env_file_path.exists():
        print(f"Warning: Environment file {env_file_path} not found for production profile; will not generate branding file", file=sys.stderr)
        return False
    try:
        # Read environment with interpolation to resolve variables
        env_vars = read_env(str(env_file_path), interpolate=True)
    except Exception as e:
        print(f"Error reading environment file {env_file_path}: {e}; will not generate branding file", file=sys.stderr)
        return False
    rebranding_dir = env_vars['REBRANDING_DIR'].strip('"')
    rebranding_path = base_dir / Path(rebranding_dir)
    branding_file_path = rebranding_path / "branding.yml"
    if not branding_file_path.exists():
        print(f"Warning: Expected branding file {branding_file_path} does not exist; will not generate branding file", file=sys.stderr)
    target_branding_file_path = base_dir / Path("repos/social-app/branding.json")
    try:
        with target_branding_file_path.open('w') as f:
            subprocess.call(["yq", "--output-format=json", str(branding_file_path)], stdout=f)
    except Exception as e:
        target_exists = target_branding_file_path.exists()
        print(f"Error generating {target_branding_file_path}: {e}. " + ("Will remove branding file" if target_exists else ""), file=sys.stderr)
        if target_exists:
            target_branding_file_path.unlink()
        return False
    if not args.silent:
        print(f"✅ Generated: {target_branding_file_path}")
    return True

def main():
    parser = argparse.ArgumentParser(
        description='Generate social-app environment files from profile configurations',
        epilog="Examples:\n"
               "  %(prog)s                           # Generate for default .env\n"
               "  %(prog)s -p prod                   # Generate for .env.prod\n"
               "  %(prog)s -p prod -p test           # Generate for multiple profiles\n"
               "  %(prog)s --test                    # Generate for .env.test\n"
               "  %(prog)s -a                        # Generate for all existing profiles\n"
               "  %(prog)s -t custom.mustache        # Use custom template\n",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument('-t', '--template-file', default='selfhost_scripts/social-env.mustache',
                       help='Mustache template file to use (default: selfhost_scripts/social-env.mustache)')
    parser.add_argument('-s', '--silent', action='store_true',
                       help='Silent mode - no output except errors')
    parser.add_argument('--dry-run', action='store_true',
                       help='Show what would be generated without writing files')
    parser.add_argument('--no-branding', action='store_true',
                        help="Don't copy branding info into branding.json")

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
        '-o', '--output', default=None,
        help='Override the filename or directory prefix (if ending with /) to output (relative to target social-app directory; defaults to .env or .env.$profile)',
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
    
    # Check template file exists
    template_path = base_dir / Path(args.template_file)
    if not template_path.exists():
        print(f"Error: Template file '{template_path}' not found", file=sys.stderr)
        return False
    
    # Read template content
    try:
        with open(template_path, 'r') as f:
            template_content = f.read()
    except Exception as e:
        print(f"Error reading template file {args.template_file}: {e}", file=sys.stderr)
        return False
    
    if not args.silent:
        print(f"🎯 Using template: {template_path}")
        print(f"🔧 Processing {len(profiles)} profile(s): {', '.join(str(p) or 'default' for p in profiles)}")
        if args.dry_run:
            print("🔍 DRY RUN MODE - No files will be written")
        print()
    
    # Process each profile
    success_count = 0
    for profile in profiles:
        if generate_social_env_for_profile(profile, template_content, args):
            success_count += 1
    if not args.no_branding:
        generate_branding_file(args)

    # Report results
    if not args.silent:
        print()
        if success_count == len(profiles):
            action = "Would generate" if args.dry_run else "Successfully generated"
            print(f"✅ {action} {success_count} environment file(s)")
        else:
            failed_count = len(profiles) - success_count
            action = "would be generated" if args.dry_run else "generated"
            print(f"⚠️  {success_count} files {action}, {failed_count} failed")
    
    return success_count == len(profiles)

if __name__ == '__main__':
    if not main():
        sys.exit(1)
