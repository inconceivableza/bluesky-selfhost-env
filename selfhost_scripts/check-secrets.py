#!/usr/bin/env python3

import argparse
import os
import sys

from env_utils import read_env, check_syntax_issues

# Import shared secret type definitions
from secret_types import (
    SecretType, parse_secret_template, get_secrets_by_type, 
    get_fixed_value_secrets, get_example_patterns
)

def get_file_info(filepath):
    """Get information about a file, including symlink resolution - shared with check-env.py"""
    from pathlib import Path
    path = Path(filepath)
    if path.is_symlink():
        target = path.resolve()
        return f"{filepath} -> {target}"
    else:
        return str(path.resolve())

def is_example_value(var_name, value):
    """Check if a value appears to be an example/dummy value that should be replaced"""
    if not value:
        return True
    
    # Check against known example patterns
    example_patterns = get_example_patterns()
    for pattern in example_patterns:
        if pattern in value:
            return True
    
    return False

def validate_secret_strength(var_name, value, secret_config):
    """Validate that secret meets security requirements"""
    if not value:
        return "empty value"
    
    # Get the secret configuration for this variable
    if var_name not in secret_config:
        return "unknown secret variable"
    
    secret_type = secret_config[var_name]['type']
    
    # Check based on secret type
    if secret_type == SecretType.COMPLEX_PASSWORD:
        # OpenSearch requires mixed case, numbers, symbols
        if len(value) < 8:
            return "too short (minimum 8 characters)"
        has_upper = any(c.isupper() for c in value)
        has_lower = any(c.islower() for c in value)
        has_digit = any(c.isdigit() for c in value)
        has_symbol = any(c in '_-!@#$%^&*' for c in value)
        
        missing = []
        if not has_upper: missing.append("uppercase letter")
        if not has_lower: missing.append("lowercase letter")
        if not has_digit: missing.append("digit")
        if not has_symbol: missing.append("symbol")
        
        if missing:
            return f"missing {', '.join(missing)}"
    
    elif secret_type == SecretType.SHORT_HEX:
        # Short keys (32 chars hex = 128 bits)
        if len(value) != 32:
            return f"wrong length (expected 32 characters, got {len(value)})"
        if not all(c in '0123456789abcdefABCDEF' for c in value):
            return "not valid hex"
    
    elif secret_type == SecretType.LONG_HEX:
        # Long keys (64 chars hex = 256 bits)
        if len(value) != 64:
            return f"wrong length (expected 64 characters, got {len(value)})"
        if not all(c in '0123456789abcdefABCDEF' for c in value):
            return "not valid hex"
    
    elif secret_type == SecretType.FIXED_VALUE:
        # Fixed values should match expected values
        expected = secret_config[var_name]['fixed_value']
        if expected and value != expected:
            return f"should be '{expected}', got '{value}'"
    
    elif secret_type == SecretType.EXTERNAL:
        # External secrets just need to have a value (can't validate content)
        if not value.strip():
            return "external secret must be manually set (currently empty)"
    
    return None

def main():
    parser = argparse.ArgumentParser(description='Check secrets file against template')
    parser.add_argument('-e', '--secrets-file', default='config/secrets-passwords.env',
                       help='Secrets file to check (default: config/secrets-passwords.env)')
    parser.add_argument('-t', '--template-file', default='config/secrets-passwords.env.example',
                       help='Template file to compare against (default: config/secrets-passwords.env.example)')
    parser.add_argument('-s', '--silent', action='store_true',
                       help='Silent mode - no output, just exit codes (0=valid, 1=issues)')
    parser.add_argument('--allow-example-values', action='store_true',
                       help='Allow example/dummy values (for testing)')
    
    args = parser.parse_args()
    
    # Check if files exist
    if not os.path.exists(args.template_file):
        if not args.silent:
            print(f"Error: Template file '{args.template_file}' not found", file=sys.stderr)
        sys.exit(1)
        
    if not os.path.exists(args.secrets_file):
        if not args.silent:
            print(f"Error: Secrets file '{args.secrets_file}' not found", file=sys.stderr)
        sys.exit(1)
    
    # Show file information (unless silent)
    if not args.silent:
        print(f"Checking secrets file:")
        print(f"  Target:   {get_file_info(args.secrets_file)}")
        print(f"  Template: {get_file_info(args.template_file)}")
        print()
    
    try:
        # Parse the template file to get secret types
        secret_config = parse_secret_template(args.template_file)
        
        # Read the actual secrets file
        secrets_vars = read_env(args.secrets_file, interpolate=False)
        
    except Exception as e:
        if not args.silent:
            print(f"Error reading files: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Check for syntax issues first
    syntax_issues = check_syntax_issues(args.secrets_file)
    
    # Track issues
    has_issues = False
    has_missing_vars = False
    has_syntax_issues = len(syntax_issues) > 0
    
    if not args.silent:
        print("=== SECRETS ANALYSIS ===\n")
        
        # Report syntax issues first
        if syntax_issues:
            for issue in syntax_issues:
                print(f"🚨 SYNTAX: {issue}")
            print()  # Add blank line after syntax issues
    
    # Check each variable in template
    for var_name in secret_config.keys():
        if var_name not in secrets_vars:
            has_issues = True
            has_missing_vars = True
            if not args.silent:
                print(f"❌ MISSING: {var_name}")
            continue
        
        value = secrets_vars[var_name]
        
        # Check for example values
        if not args.allow_example_values and is_example_value(var_name, value):
            has_issues = True
            if not args.silent:
                print(f"⚠️  EXAMPLE VALUE: {var_name} (still using template/example value)")
            continue
        
        # Validate secret strength
        strength_issue = validate_secret_strength(var_name, value, secret_config)
        if strength_issue:
            has_issues = True
            if not args.silent:
                print(f"🔒 WEAK SECRET: {var_name} ({strength_issue})")
            continue
    
    # Check for extra variables
    extra_vars = [v for v in secrets_vars.keys() if v not in secret_config]
    if extra_vars:
        has_issues = True
        if not args.silent:
            print(f"ℹ️  EXTRA VARIABLES: {', '.join(sorted(extra_vars))}")
    
    if not args.silent and not has_issues and not has_syntax_issues:
        print("✅ All secrets are properly configured!")
    
    # Exit with error code if there are missing variables or syntax issues
    if has_missing_vars or has_syntax_issues:
        if not args.silent:
            error_parts = []
            if has_syntax_issues:
                error_parts.append("syntax errors")
            if has_missing_vars:
                error_parts.append("missing variables")
            
            error_msg = " and ".join(error_parts)
            print(f"❌ Error: there are {error_msg} in this file")
        sys.exit(1)

if __name__ == '__main__':
    main()