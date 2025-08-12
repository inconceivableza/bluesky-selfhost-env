#!/bin/sh
"exec" """$(dirname $0)/venv/bin/python""" "$0" "$@" # this is a polyglot shell exec which will drop down to the relative virtualenv's python

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
        
        # Read existing secrets and file content if file exists
        existing_vars = {}
        existing_content = ""
        if os.path.exists(args.secrets_file):
            existing_vars = read_env(args.secrets_file, interpolate=False)
            with open(args.secrets_file, 'r') as f:
                existing_content = f.read()
        
        # Generate only new secrets that don't exist
        new_secrets = {}
        external_secrets = []
        
        for var_name, config in secret_config.items():
            # Skip if variable already exists in file
            if var_name in existing_vars:
                continue
                
            secret_type = config['type']
            fixed_value = config['fixed_value']
            
            if secret_type == SecretType.FIXED_VALUE and fixed_value:
                # Use fixed value
                new_secrets[var_name] = fixed_value
            elif secret_type == SecretType.EXTERNAL:
                # External secrets need manual intervention
                external_secrets.append(var_name)
                new_secrets[var_name] = ""  # Empty placeholder
            else:
                # Generate new secret
                generator = get_secret_generator(secret_type)
                if generator:
                    new_secrets[var_name] = generator()
                else:
                    print(f"Warning: Unknown secret type '{secret_type}' for {var_name}", file=sys.stderr)
                    new_secrets[var_name] = ""
        
        # Build final content: existing content + new secrets
        if existing_content:
            # Start with existing content
            output_content = existing_content
            # Ensure it ends with a newline
            if not output_content.endswith('\n'):
                output_content += '\n'
            
            # Add new secrets if any
            if new_secrets:
                for var_name in secret_config.keys():  # Preserve template order for new variables
                    if var_name in new_secrets:
                        output_content += f"{var_name}={new_secrets[var_name]}\n"
        else:
            # No existing file, create from scratch
            output_lines = []
            for var_name, config in secret_config.items():
                secret_type = config['type']
                fixed_value = config['fixed_value']
                
                if secret_type == SecretType.FIXED_VALUE and fixed_value:
                    value = fixed_value
                elif secret_type == SecretType.EXTERNAL:
                    if var_name not in external_secrets:
                        external_secrets.append(var_name)
                    value = ""
                else:
                    generator = get_secret_generator(secret_type)
                    value = generator() if generator else ""
                
                output_lines.append(f"{var_name}={value}")
            
            output_content = '\n'.join(output_lines) + '\n'
        
        # Write to the secrets file
        with open(args.secrets_file, 'w') as f:
            f.write(output_content)
        # Report what was done
        if new_secrets:
            print(f"Added {len(new_secrets)} new secrets to {args.secrets_file}", file=sys.stderr)
        else:
            print(f"All secrets already exist in {args.secrets_file}", file=sys.stderr)
        
        # Notify user about external secrets that need manual setup
        if external_secrets:
            print("\n❌  EXTERNAL SECRETS REQUIRED:", file=sys.stderr)
            print("The following secrets are externally generated and must be manually added:", file=sys.stderr)
            for var_name in external_secrets:
                print(f"  - {var_name}: Edit {args.secrets_file} to provide this value", file=sys.stderr)
            print(f"\nPlease edit {args.secrets_file} and set values for these external secrets.", file=sys.stderr)
            
    except Exception as e:
        print(f"Error generating secrets: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
