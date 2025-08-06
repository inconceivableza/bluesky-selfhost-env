#!/usr/bin/env python3

import argparse
import os
import sys
import re
from pathlib import Path

from env_utils import read_env, replace_env
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
    """Parse env file and preserve variable order, including optional variables"""
    variables = []
    optional_variables = []
    try:
        with open(filepath, 'r') as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                if line:
                    # Check for optional variables (commented out)
                    if line.startswith('# ') and '=' in line:
                        # Extract variable name from commented line
                        uncommented = line[2:]  # Remove '# '
                        if '=' in uncommented:
                            key = uncommented.split('=', 1)[0].strip()
                            optional_variables.append(key)
                    # Check for regular variables
                    elif not line.startswith('#') and '=' in line:
                        key = line.split('=', 1)[0]
                        variables.append(key)
    except FileNotFoundError:
        pass
    return variables, optional_variables

def extract_variable_references(value):
    """Extract variable references like ${varname} from a value"""
    if not value:
        return []
    return re.findall(r'\$\{([^}]+)\}', value)

def compare_variable_definitions(example_val, target_val):
    """Compare variable definitions - return True if example uses variables and strings differ"""
    if not example_val or not target_val:
        return False
    
    # If example uses variables and the strings are different, it's a definition change
    example_vars = extract_variable_references(example_val)
    if example_vars and example_val != target_val:
        return True
    
    return False

def main():
    parser = argparse.ArgumentParser(description='Compare .env file with bluesky-params.env.example')
    parser.add_argument('-e', '--env-file', default='.env', help='Environment file to check (default: .env)')
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
    
    args = parser.parse_args()
    
    # Check if files exist
    if not os.path.exists(args.template_file):
        print(f"Error: Example file '{args.template_file}' not found", file=sys.stderr)
        sys.exit(1)
        
    if not os.path.exists(args.env_file):
        print(f"Error: Environment file '{args.env_file}' not found", file=sys.stderr)
        sys.exit(1)
    
    # Show file information (unless silent)
    if not args.silent:
        print(f"Comparing files:")
        print(f"  Target:  {get_file_info(args.env_file)}")
        print(f"  Example: {get_file_info(args.template_file)}")
        print()
    
    # Read environment files and secret variable names
    try:
        example_env = read_env(args.template_file, interpolate=False)
        example_env_resolved = read_env(args.template_file, interpolate=True)
        target_env = read_env(args.env_file, interpolate=False)
        target_env_resolved = read_env(args.env_file, interpolate=True)
        
        # Load secret variable names if secrets template exists
        secret_vars = set()
        if os.path.exists(args.secrets_template):
            secret_config = parse_secret_template(args.secrets_template)
            secret_vars = set(secret_config.keys())
        
    except Exception as e:
        print(f"Error reading environment files: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Get variable order from both files
    example_order, example_optional = parse_env_with_order(args.template_file)
    target_order, target_optional = parse_env_with_order(args.env_file)
    
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
    
    # Track issues and critical errors (missing vars + exposed passwords)  
    has_issues = False
    has_missing_vars = False
    has_exposed_passwords = False
    
    if not args.silent:
        print("=== ANALYSIS ===\n")
    
    # Process all variables in order
    for var in all_vars:
        example_val = example_env.get(var)
        example_resolved = example_env_resolved.get(var)
        target_val = target_env.get(var)
        target_resolved = target_env_resolved.get(var) if target_val else None
        
        # Always show missing REQUIRED variables (in example but not optional and not in target)
        if var in example_env and var not in target_env:
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
        if (args.show_value_changes and 
            var in example_env and var in target_env and
            not extract_variable_references(example_val) and  # example doesn't use variables
            example_val != target_val):  # but values are different
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
    
    if not args.silent and not has_issues:
        print("✅ All variables match between files!")
    
    # Exit with error code if there are missing variables or exposed passwords
    if has_missing_vars or has_exposed_passwords:
        if not args.silent:
            print(f"❌ Error: there are {'missing variables' if has_missing_vars else ''}"
                  f"{' and ' if has_missing_vars and has_exposed_passwords else ''}"
                  f"{'exposed passwords' if has_exposed_passwords else ''} in this file")
        sys.exit(1)

if __name__ == '__main__':
    main()