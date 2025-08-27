#!/bin/sh
"exec" """$(dirname $0)/venv/bin/python""" "$0" "$@" # this is a polyglot shell exec which will drop down to the relative virtualenv's python

import argparse
import os
import sys
import re
from pathlib import Path

from env_utils import check_syntax_issues, get_profile_env_paths, get_existing_profile_names,  read_env, validate_profile_name
from secret_types import parse_secret_template

def get_file_info(filepath):
    """Get information about a file, including symlink resolution"""
    path = Path(filepath)
    if path.is_symlink():
        target = path.resolve()
        return f"{filepath} -> {target}"
    else:
        return str(path.resolve())

def parse_env_with_order(filepath):
    """Parse env file and preserve variable order, including optional variables with values"""
    variables = []
    optional_variables = []
    optional_values = {}  # Store optional variable values from comments

    try:
        with open(filepath, 'r') as f:
            for line_num, line in enumerate(f, 1):
                original_line = line.strip()
                if original_line:
                    # Check for optional variables (commented out) - format: # key=value  # optional comment
                    if original_line.startswith('# ') and '=' in original_line:
                        # Remove initial '# ' and split on first '='
                        uncommented = original_line[2:]  # Remove '# '
                        if '=' in uncommented:
                            # Split on first '=' to get key and value part
                            key, value_part = uncommented.split('=', 1)
                            key = key.strip()

                            # Handle case where there's a comment after the value: value # comment
                            if '#' in value_part:
                                value = value_part.split('#', 1)[0].strip()
                            else:
                                value = value_part.strip()

                            optional_variables.append(key)
                            optional_values[key] = value
                    # Check for regular variables
                    elif not original_line.startswith('#') and '=' in original_line:
                        key = original_line.split('=', 1)[0]
                        if re.match('^[a-zA-Z0-9_]+$', key):
                            if key.startswith('_'):
                                optional_variables.append(key)
                                # For underscore variables, also extract their value
                                value = original_line.split('=', 1)[1]
                                if '#' in value:
                                    value = value.split('#', 1)[0].strip()
                                optional_values[key] = value
                            else:
                                variables.append(key)
    except FileNotFoundError:
        pass

    # Remove variables from optional list if they're real variables, but keep their optional values
    # This allows optional values to serve as alternative acceptable values for comparison
    for non_optional in set(variables).intersection(optional_variables):
        optional_variables.remove(non_optional)
        # Keep the optional_values - they can be used for value comparison

    return variables, optional_variables, optional_values

def extract_variable_references(value):
    """Extract variable references like ${varname} and ${varname:-fallback} from a value"""
    if not value:
        return []
    # Find all ${...} patterns and extract the variable names
    matches = re.findall(r'\$\{([^}]+)\}', value)
    var_names = []
    for match in matches:
        # For ${VAR:-fallback}, extract just the VAR part
        if ':-' in match:
            var_name = match.split(':-')[0]
            var_names.append(var_name)
        else:
            var_names.append(match)
    return var_names

def compare_variable_definitions(example_val, target_val):
    """Compare variable definitions - return True if example uses variables and strings differ"""
    if not example_val or not target_val:
        return False

    # If example uses variables and the strings are different, it's a definition change
    example_vars = extract_variable_references(example_val)
    if example_vars and example_val != target_val:
        return True

    return False

def check_ssl_configuration(target_env):
    """Check SSL certificate configuration consistency"""
    ssl_errors = []

    # Check if EMAIL4CERTS is set to 'internal' (self-signed certificates)
    email4certs = target_env.get('EMAIL4CERTS', '').strip()

    if email4certs == 'internal':
        # For self-signed certificates, these should be configured correctly
        custom_certs_dir = target_env.get('CUSTOM_CERTS_DIR', '').strip()
        update_certs_cmd = target_env.get('UPDATE_CERTS_CMD', '').strip()

        # Check CUSTOM_CERTS_DIR should be /etc/ssl/certs or /usr/local/share/ca-certificates
        if custom_certs_dir not in ('/etc/ssl/certs', '/usr/local/share/ca-certificates'):
            ssl_errors.append(('CUSTOM_CERTS_DIR', f"EMAIL4CERTS='internal' but CUSTOM_CERTS_DIR is '{custom_certs_dir}', should be '/etc/ssl/certs' or '/usr/local/share/ca-certificates'"))

        # Check UPDATE_CERTS_CMD should contain update-ca-certificates
        if 'update-ca-certificates' not in update_certs_cmd:
            ssl_errors.append(('UPDATE_CERTS_CMD', f"EMAIL4CERTS='internal' but UPDATE_CERTS_CMD is '{update_certs_cmd}', should contain 'update-ca-certificates'"))

        # Also add the main EMAIL4CERTS error to indicate the inconsistency source
        if ssl_errors:
            ssl_errors.insert(0, ('EMAIL4CERTS', f"Set to 'internal' but certificate configuration is inconsistent"))

    return ssl_errors

def check_single_env_file(env_file, args):
    """Check a single environment file against the template."""
    # Check if files exist
    if not os.path.exists(args.template_file):
        print(f"Error: Example file '{args.template_file}' not found", file=sys.stderr)
        return False

    if not os.path.exists(env_file):
        print(f"Error: Environment file '{env_file}' not found", file=sys.stderr)
        return False

    # Show file information (unless silent)
    if not args.silent:
        print(f"Comparing files:")
        print(f"  Target:  {get_file_info(env_file)}")
        print(f"  Example: {get_file_info(args.template_file)}")
        print()

    # Read environment files and secret variable names
    try:
        example_env = read_env(args.template_file, interpolate=False)
        example_env_resolved = read_env(args.template_file, interpolate=True)
        target_env = read_env(env_file, interpolate=False)
        target_env_resolved = read_env(env_file, interpolate=True)

        # Load secret variable names if secrets template exists
        secret_vars = set()
        if os.path.exists(args.secrets_template):
            secret_config = parse_secret_template(args.secrets_template)
            secret_vars = set(secret_config.keys())

    except Exception as e:
        print(f"Error reading environment files: {e}", file=sys.stderr)
        return False

    # Get variable order from both files
    example_order, example_optional, example_optional_values = parse_env_with_order(args.template_file)
    target_order, _target_optional, _target_optional_values = parse_env_with_order(env_file)

    # Combine all known variables (required + optional) from example
    example_all_vars = set(example_order + example_optional)

    # Create combined order: example variables first, then target-only variables
    all_vars = []
    seen = set()

    # Add example variables in order
    for var in example_order:
        if var not in seen:
            all_vars.append(var)
            seen.add(var)

    # Add example optional variables in order
    for var in example_optional:
        if var not in seen:
            all_vars.append(var)
            seen.add(var)

    # Add target variables not in example, in target order
    for var in target_order:
        if var not in seen:
            all_vars.append(var)
            seen.add(var)

    # Check for syntax issues first
    syntax_issues = check_syntax_issues(env_file)

    # Check SSL configuration consistency
    ssl_errors = check_ssl_configuration(target_env)

    # Track issues and critical errors (missing vars + exposed passwords + syntax issues + ssl errors)
    has_issues = False
    has_missing_vars = False
    has_exposed_passwords = False
    has_syntax_issues = len(syntax_issues) > 0
    has_ssl_errors = len(ssl_errors) > 0

    if not args.silent:
        print("=== ANALYSIS ===")
        print()

        # Report syntax issues first
        if syntax_issues:
            for issue in syntax_issues:
                print(f"🚨 SYNTAX: {issue}")
            print()  # Add blank line after syntax issues

        # Report SSL configuration errors
        if ssl_errors:
            for var_name, error_msg in ssl_errors:
                print(f"🔒 SSL_ERROR: {var_name}. {error_msg}")
            print()  # Add blank line after SSL errors

    # Process all variables in order
    for var in all_vars:
        example_val = example_env.get(var)
        example_resolved = example_env_resolved.get(var)
        target_val = target_env.get(var)
        target_resolved = target_env_resolved.get(var) if target_val else None

        # Always show missing REQUIRED variables (in example but not optional and not in target)
        if var in example_env and var not in target_env and var not in example_optional:
            has_issues = True
            has_missing_vars = True
            if not args.silent:
                if example_resolved != example_val:
                    print(f"❌ MISSING: {var}. Example: {example_val} -> {example_resolved}")
                else:
                    print(f"❌ MISSING: {var}. Example: {example_val}")
            continue

        # Show definition changes if requested
        if (args.show_definition_changes and
            var in example_env and var in target_env and
            compare_variable_definitions(example_val, target_val)):
            has_issues = True
            if not args.silent:
                example_display = f"{example_val} -> {example_resolved}" if example_resolved != example_val else example_val
                target_display = f"{target_val} -> {target_resolved}" if target_resolved != target_val else target_val
                print(f"⚠️  DEFINITION CHANGE: {var}. Example: {example_display}, Target: {target_display}")
            continue

        # Show value changes if requested (plain values, no variable substitution)
        # But don't report a difference if the value matches an optional value defined in a comment
        if (args.show_value_changes and
            var in example_env and var in target_env and
            not extract_variable_references(example_val) and  # example doesn't use variables
            example_val != target_val):  # but values are different

            # Check if target value matches an optional value from example comments
            optional_match = (var in example_optional_values and
                            target_val == example_optional_values[var])

            if not optional_match:
                has_issues = True
                if not args.silent:
                    print(f"📝 VALUE CHANGE: {var}. Example: {example_val}, Target: {target_val}")
                continue

        # Check for exposed passwords (secret variables in environment file)
        if (var not in example_all_vars and var in target_env and var in secret_vars):
            has_issues = True
            has_exposed_passwords = True
            if not args.silent:
                if target_resolved != target_val:
                    print(f"🚨 EXPOSED PASSWORD: {var}. Value: {target_val} -> {target_resolved}")
                else:
                    print(f"🚨 EXPOSED PASSWORD: {var}. Value: {target_val}")
            continue

        # Show extra variables in target (unless hidden) - but skip optional variables
        if (not args.hide_extra_vars and
            var not in example_all_vars and var in target_env):
            has_issues = True
            if not args.silent:
                if target_resolved != target_val:
                    print(f"ℹ️  EXTRA: {var}. Value: {target_val} -> {target_resolved}")
                else:
                    print(f"ℹ️  EXTRA: {var}. Value: {target_val}")

    if not args.silent and not has_issues and not has_syntax_issues and not has_ssl_errors:
        print("✅ All variables match between files!")

    # Return True if no critical errors (missing vars, exposed passwords, syntax issues, or SSL errors)
    return not (has_missing_vars or has_exposed_passwords or has_syntax_issues or has_ssl_errors)


def main():
    parser = argparse.ArgumentParser(
        description='Compare .env file with bluesky-params.env.example',
        epilog="Examples:\n"
               "  %(prog)s                           # Check .env\n"
               "  %(prog)s -p prod                   # Check .env.prod\n"
               "  %(prog)s -p prod -p staging        # Check multiple profiles\n"
               "  %(prog)s --staging                 # Check .env.staging\n"
               "  %(prog)s -a                        # Check all existing .env* files\n"
               "  %(prog)s -e custom.env             # Check custom.env\n",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument('-e', '--env-file', help='Environment file to check (overrides profile options)')
    parser.add_argument('-t', '--template-file', default='bluesky-params.env.example',
                       help='Template file to compare against (default: bluesky-params.env.example)')
    parser.add_argument('-d', '--show-definition-changes', action='store_true',
                       help='Show variables that use different variable references')
    parser.add_argument('-v', '--show-value-changes', action='store_true',
                       help='Show variables with different plain values (no variable substitution)')
    parser.add_argument('-q', '--hide-extra-vars', action='store_true',
                       help='Hide variables in target that are not in example (default: show them)')
    parser.add_argument('-s', '--silent', action='store_true',
                       help='Silent mode - no output, just exit codes (0=match, 1=differences)')
    parser.add_argument('--secrets-template', default='config/secrets-passwords.env.example',
                       help='Secrets template file to check for exposed passwords')

    parser.add_argument(
        '-p', '--profile',
        action='append',
        dest='profiles',
        default=[],
        help='Target profile for .env.{profile} (allows [a-zA-Z0-9_.+-] characters, can be used multiple times)'
    )
    parser.add_argument(
        '-P', '--prod',
        action='append_const',
        const='production',
        dest='profiles',
        help='Shortcut for --profile production'
    )
    parser.add_argument(
        '-D', '--default',
        action='append_const',
        const='default',
        dest='profiles',
        help='Shortcut for --profile default which targets the main .env file'
    )
    parser.add_argument(
        '-S', '--staging',
        action='append_const',
        const='staging',
        dest='profiles',
        help='Shortcut for --profile staging'
    )
    parser.add_argument(
        '-a', '--all-profiles',
        action='store_true',
        help='Check all existing .env* files'
    )

    args = parser.parse_args()

    # Handle profile selection
    profiles = [None if p == 'default' else p for p in args.profiles] or []
    default_profiles = [None, "production", "staging"]

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

    # Determine which files to check
    if args.env_file and profiles and profiles != [None]:
        parser.error("Either specify env file or profiles, not both")
    if args.env_file:
        # Explicit file specified
        env_files = [args.env_file]
    else:
        # Use profile-based files
        env_files = get_profile_env_paths(profiles)

        # Check if any files exist
        existing_files = [f for f in env_files if os.path.exists(f)]
        if not existing_files:
            print(f"No environment files found for specified profiles: {', '.join(str(p) or '.env' for p in profiles)}", file=sys.stderr)
            return False

    # Check all specified files
    problem_env_files = []
    for i, env_file in enumerate(env_files):
        if len(env_files) > 1 and not args.silent:
            if i > 0:
                print("\n" + "="*60 + "\n")
            print(f"📁 Checking file {i+1} of {len(env_files)}: {env_file}")
            print()

        if not check_single_env_file(env_file, args):
            problem_env_files.append(env_file.name)

    # Exit with appropriate code
    if problem_env_files:
        if not args.silent:
            print(f"\n❌ The following environment files have issues: {', '.join(problem_env_files)}")
        return False
    elif not args.silent and len(env_files) > 1:
        print(f"\n✅ All {len(env_files)} environment files are valid!")
    return True

if __name__ == '__main__':
    if not main():
        sys.exit(1)
