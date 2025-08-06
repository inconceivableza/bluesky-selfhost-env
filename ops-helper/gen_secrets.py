#!/usr/bin/env python3

import argparse
import os
import sys
import secrets
import subprocess
import string

from env_utils import read_env

def generate_long_key():
    """Generate a 64-character hex key (256 bits) equivalent to openssl ecparam method"""
    return secrets.token_hex(32)

def generate_short_key():
    """Generate a 32-character hex key (128 bits) equivalent to openssl rand --hex 16"""
    return secrets.token_hex(16)

def generate_random_password():
    """Generate a strong password with capitals, numbers, and symbols for OpenSearch"""
    # Ensure at least one of each required character type
    chars = string.ascii_lowercase + string.ascii_uppercase + string.digits + "_-"
    password = [
        secrets.choice(string.ascii_uppercase),
        secrets.choice(string.digits),
        secrets.choice("_-"),
    ]
    # Fill the rest randomly
    for _ in range(7):  # Total length 10
        password.append(secrets.choice(chars))
    
    # Shuffle to avoid predictable patterns
    secrets.SystemRandom().shuffle(password)
    return ''.join(password) + '_'

# Import shared secret type definitions
from secret_types import SecretType, parse_secret_template, get_fixed_value_secrets

def get_secret_generator(secret_type):
    """Get the appropriate generator function for a secret type"""
    generators = {
        SecretType.LONG_HEX: generate_long_key,
        SecretType.SHORT_HEX: generate_short_key,
        SecretType.COMPLEX_PASSWORD: generate_random_password,
    }
    return generators.get(secret_type)

def main():
    parser = argparse.ArgumentParser(description='Generate secrets for bluesky self-hosting')
    parser.add_argument('-t', '--template-file', 
                       default='config/secrets-passwords.env.example',
                       help='Template file with all required secrets')
    parser.add_argument('secrets_file', nargs='?',
                       default='config/secrets-passwords.env',
                       help='Secrets file to create/update (default: config/secrets-passwords.env)')
    
    args = parser.parse_args()
    
    # Check if template file exists
    if not os.path.exists(args.template_file):
        print(f"Error: Template file '{args.template_file}' not found", file=sys.stderr)
        sys.exit(1)
    
    try:
        # Parse template to get secret configuration
        secret_config = parse_secret_template(args.template_file)
        
        # Read existing secrets if file exists
        existing_vars = {}
        if os.path.exists(args.secrets_file):
            existing_vars = read_env(args.secrets_file, interpolate=False)
        
        # Generate secrets
        output_vars = {}
        
        for var_name, config in secret_config.items():
            secret_type = config['type']
            fixed_value = config['fixed_value']
            
            if var_name in existing_vars:
                # Preserve existing value
                output_vars[var_name] = existing_vars[var_name]
            elif secret_type == SecretType.FIXED_VALUE and fixed_value:
                # Use fixed value
                output_vars[var_name] = fixed_value
            else:
                # Generate new secret
                generator = get_secret_generator(secret_type)
                if generator:
                    output_vars[var_name] = generator()
                else:
                    print(f"Warning: Unknown secret type '{secret_type}' for {var_name}", file=sys.stderr)
                    output_vars[var_name] = ""
        
        # Output results
        output_lines = []
        for var_name in secret_config.keys():  # Preserve order from template
            output_lines.append(f"{var_name}={output_vars[var_name]}")
        
        output_content = '\n'.join(output_lines) + '\n'
        
        # Write to the secrets file
        with open(args.secrets_file, 'w') as f:
            f.write(output_content)
        print(f"Secrets written to {args.secrets_file}", file=sys.stderr)
            
    except Exception as e:
        print(f"Error generating secrets: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()