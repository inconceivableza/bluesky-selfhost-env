#!/bin/sh
"exec" """$(dirname $0)/venv/bin/python""" "$0" "$@" # this is a polyglot shell exec which will drop down to the relative virtualenv's python

"""
Generate example google services json file for social-app for eas profiles

This is because the google-services.json selected file needs to correspond to the package name generated in social-app/app.config.js
This script reads environment variables from profile files and generates
corresponding .env files for the social-app Docker image using a mustache template.
"""

import argparse
import json
import sys
import yaml
from pathlib import Path

from env_utils import get_branding_filename

base_dir = Path(__file__).parent.parent

is_example = True # this is still using -example suffixes

def get_output_path(profile, args):
    """Get the output path for social-app env file based on profile."""
    base_path = base_dir / Path("repos/social-app")
    if args.output:
        return base_path / Path(args.output) # will compute as relative unless absolute
    
    if profile is None:
        return base_path / "google-services.json"
    else:
        return base_path / f"google-services.{profile}.json"

PACKAGE_NAME_PROFILE_SUFFIXES = {
    '': '',
    'development': '.dev',
    'preview': '.preview',
    'testflight': '.testflight',
    'production': '',
}

def get_branding():
    branding_file = get_branding_filename()
    if not branding_file:
        print(f"error locating branding file; will not customize google-services for branding", file=sys.stderr)
        return {}
    with open(branding_file, 'r') as f:
        return yaml.safe_load(f)

def patch_google_services_content(template_content, profile):
    branding = get_branding()
    gs_project_name = branding.get('code', {}).get('google_service_project_name', 'blueskyweb')
    if is_example:
        gs_project_name += '-example'
    gs_firebase_url = f'https://{gs_project_name}.firebaseio.com'
    package_name = branding.get('code', {}).get('web_package_id', 'xyz.blueskyweb.app')
    profile_suffix = PACKAGE_NAME_PROFILE_SUFFIXES.get(profile)
    profile_package_name = package_name + profile_suffix
    gs = json.loads(template_content)
    patched = False
    old_project_id = gs['project_info']['project_id']
    old_firebase_url = gs['project_info']['firebase_url']
    gs['project_info']['project_id'] = gs_project_name
    gs['project_info']['firebase_url'] = gs_firebase_url
    patched = old_project_id != gs_project_name or old_firebase_url != gs_firebase_url
    for client in gs.get('client', []):
        android_client_info = client.get('client_info', {}).get('android_client_info', {})
        if android_client_info and 'package_name' in android_client_info:
            old_package_name = android_client_info.get('package_name')
            android_client_info['package_name'] = profile_package_name
            patched = old_package_name != old_package_name != profile_package_name
    if not patched:
        print(f"No changes were made to google services content for {profile}", file=sys.stderr)
    return gs
    
def generate_google_services_for_profile(profile, template_content, args):
    """Generate social-app environment file for a specific profile."""
    output_path = get_output_path(profile, args)

    gs_content = patch_google_services_content(template_content, profile)

    if args.dry_run:
        if not args.silent:
            print(f"🔍 Would generate: {output_path}")
            print("Content:")
            print(gs_content)
            print("-" * 40)
        return True
    
    # Ensure output directory exists
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        if not args.no_check:
            try:
                with output_path.open('r') as f:
                    existing_content = json.load(f)
                matches = existing_content == gs_content
            except Exception as e:
                print(f"Error reading {output_path} to check content; will assume differs: {e}")
                matches = False
            if matches:
                if not args.silent:
                    print(f"✅ Content in {output_path} matches what this script would produce")
                return True
            else:
                print(f"Content in {output_path} doesn't match what this script would produce", file=sys.stderr)
        if args.force:
            if not args.silent:
                print(f"Will overwrite {output_path}")
        else:
            if not args.silent:
                print(f"Will not overwrite {output_path}")
            return not matches
    try:
        with output_path.open('w') as f:
            json.dump(gs_content, f)
        if not args.silent:
            print(f"✅ Generated: {output_path}")
    except Exception as e:
        print(f"Error writing output file {output_path}: {e}", file=sys.stderr)
        return False
    return True


def main():
    parser = argparse.ArgumentParser(
        description='Generate google-services.*.json files from build configurations',
        epilog="Examples:\n"
               "  %(prog)s                           # Generate for default .env\n"
               "  %(prog)s -p prod                   # Generate for .env.prod\n"
               "  %(prog)s -p prod -p test           # Generate for multiple profiles\n"
               "  %(prog)s --test                    # Generate for .env.test\n"
               "  %(prog)s -a                        # Generate for all existing profiles\n"
               "  %(prog)s -t custom.mustache        # Use custom template\n",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument('-t', '--template-file', default='repos/social-app/google-services.json',
                       help='JSON template file to use (default: repos/social-app/google-services.json)')
    parser.add_argument('-s', '--silent', action='store_true',
                       help='Silent mode - no output except errors')
    parser.add_argument('-f', '--force', action='store_true',
                       help='Force overwriting files even if they exist (will skip by default)')
    parser.add_argument('--no-check', action='store_true',
                       help='If not overwriting files, ignore them rather than checking if the content is as expected')
    parser.add_argument('--dry-run', action='store_true',
                       help='Show what would be generated without writing files')

    parser.add_argument(
        '-p', '--profile',
        action='append',
        dest='profiles',
        default=[],
        help='Target profile for google-services.{profile}.json (allows [a-zA-Z0-9_.+-] characters, can be used multiple times)'
    )
    parser.add_argument(
        '-P', '--prod',
        action='append_const',
        const='production',
        dest='profiles',
        help='Shortcut for --profile production'
    )
    parser.add_argument(
        '-T', '--testflight',
        action='append_const',
        const='testflight',
        dest='profiles',
        help='Shortcut for --profile testflight'
    )
    parser.add_argument(
        '-V', '--preview',
        action='append_const',
        const='preview',
        dest='profiles',
        help='Shortcut for --profile preview'
    )
    parser.add_argument(
        '-D', '--dev',
        action='append_const',
        const='development',
        dest='profiles',
        help='Shortcut for --profile development'
    )

    parser.add_argument(
        '-o', '--output', default=None,
        help='Override the filename to output (relative to target social-app directory; defaults to google-services.$profile.json)',
    )
    
    args = parser.parse_args()
    
    # If no profiles specified, default to None (which means .env)
    if not args.profiles:
        parser.error("At least one profile must be specified")
    
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
        print(f"🔧 Processing {len(args.profiles)} profile(s): {', '.join(args.profiles)}")
        if args.dry_run:
            print("🔍 DRY RUN MODE - No files will be written")
        print()
    
    # Process each profile
    success_count = 0
    for profile in args.profiles:
        if generate_google_services_for_profile(profile, template_content, args):
            success_count += 1
    
    # Report results
    if not args.silent:
        print()
        if success_count == len(args.profiles):
            action = "Would generate" if args.dry_run else "Successfully generated"
            print(f"✅ {action} {success_count} environment file(s)")
        else:
            failed_count = len(args.profiles) - success_count
            action = "would be generated" if args.dry_run else "generated"
            print(f"⚠️  {success_count} files {action}, {failed_count} failed")
    
    return success_count == len(args.profiles)

if __name__ == '__main__':
    if not main():
        sys.exit(1)
