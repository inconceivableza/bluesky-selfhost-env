#!/usr/bin/env python3

"""
Shared module for secret type definitions and parsing.
Used by both check-secrets.py and gen_secrets.py to ensure consistency.
"""

import os
import re
import sys
from enum import Enum

from env_utils import read_env

class SecretType(Enum):
    """Enumeration of secret types"""
    LONG_HEX = "long_hex"
    SHORT_HEX = "short_hex"  
    COMPLEX_PASSWORD = "complex_password"
    FIXED_VALUE = "fixed_value"
    EXTERNAL = "external"

def parse_secret_template(template_file):
    """
    Parse the secrets template file to extract variable names, types, and fixed values.
    
    Returns:
        dict: {variable_name: {'type': SecretType, 'fixed_value': str or None}}
    """
    if not os.path.exists(template_file):
        raise FileNotFoundError(f"Template file not found: {template_file}")
    
    secrets_config = {}
    
    with open(template_file, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            
            # Skip comments and empty lines
            if not line or line.startswith('#'):
                continue
                
            # Look for variable definitions with type comments
            # Format: VARIABLE_NAME=value # type or # type:value
            if '=' in line and '#' in line:
                var_part, comment_part = line.split('#', 1)
                var_name = var_part.split('=', 1)[0].strip()
                comment = comment_part.strip()
                
                # Parse the type comment
                if ':' in comment:
                    # Format: # fixed_value:actual_value
                    type_str, fixed_value = comment.split(':', 1)
                    type_str = type_str.strip()
                    fixed_value = fixed_value.strip()
                else:
                    # Format: # long_hex
                    type_str = comment.strip()
                    fixed_value = None
                
                # Convert string to enum
                try:
                    secret_type = SecretType(type_str)
                except ValueError:
                    print(f"Warning: Unknown secret type '{type_str}' for {var_name} at line {line_num}", file=sys.stderr)
                    continue
                
                secrets_config[var_name] = {
                    'type': secret_type,
                    'fixed_value': fixed_value
                }
    
    return secrets_config

def get_secrets_by_type(secrets_config, secret_type):
    """Get all variable names that match a specific secret type"""
    return {name for name, config in secrets_config.items() 
            if config['type'] == secret_type}

def get_fixed_value_secrets(secrets_config):
    """Get mapping of variable names to their fixed values"""
    return {name: config['fixed_value'] 
            for name, config in secrets_config.items() 
            if config['type'] == SecretType.FIXED_VALUE and config['fixed_value'] is not None}

def get_example_patterns():
    """Return patterns that indicate example/dummy values"""
    return {
        '0123456789abcdef',  # Hex pattern from old examples
        'password',          # Default postgres password  
        'did:example:labeler',  # Example DID
        'ExamplePass123_',   # Example OpenSearch password
    }