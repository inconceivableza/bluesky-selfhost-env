#!/usr/bin/env python3

import configparser
import re

def create_env_parser():
    """Create a new environment parser instance"""
    parser = configparser.RawConfigParser(delimiters=('=',), comment_prefixes=('#',), inline_comment_prefixes=('#',))
    parser.optionxform = lambda option: option
    return parser

def read_env(filename, interpolate=False):
    """Read environment file in docker format with support for comments and variable interpolation"""
    # Use a fresh parser instance each time to avoid state persistence
    env_parser = create_env_parser()
    dummy_header_prefix = f'[{env_parser.default_section}]\n'
    
    with open(filename, 'r') as f:
        env_src = f.read()
    env_parser.read_string(dummy_header_prefix + env_src)
    env_dict = dict(env_parser[env_parser.default_section].items())
    
    if interpolate:
        # Keep interpolating until no more changes occur (to handle nested variables)
        changed = True
        while changed:
            changed = False
            for key, value in env_dict.items():
                new_value = replace_env(value, env_dict)
                if new_value != value:
                    env_dict[key] = new_value
                    changed = True
    
    return env_dict

def replace_env(src, env):
    """Replace ${keyname} and ${keyname:-fallback} with values in src"""
    if not isinstance(src, str):
        return src
    
    # First handle ${VARNAME:-fallback} syntax
    def replace_fallback(match):
        var_name = match.group(1)
        fallback = match.group(2)
        
        # Use the variable value if it exists and is not empty, otherwise use fallback
        var_value = env.get(var_name, '')
        if var_value:
            return var_value
        else:
            return fallback
    
    # Pattern to match ${VARNAME:-fallback}
    fallback_pattern = r'\$\{([A-Za-z_][A-Za-z0-9_]*):-([^}]*)\}'
    src = re.sub(fallback_pattern, replace_fallback, src)
    
    # Then handle regular ${VARNAME} syntax for remaining variables
    for key, value in sorted(env.items()):
        src = src.replace('${%s}' % key, value)
    
    return src