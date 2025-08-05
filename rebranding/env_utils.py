#!/usr/bin/env python3

import configparser

env_parser = configparser.RawConfigParser(delimiters=('=',), comment_prefixes=('#',), inline_comment_prefixes=('#',))
env_parser.optionxform = lambda option: option
dummy_header_prefix = f'[{env_parser.default_section}]\n'

def read_env(filename, interpolate=False):
    """Read environment file in docker format with support for comments and variable interpolation"""
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
    """Replace ${keyname} with values in src wherever keyname is defined in env, but otherwise leaves unchanged"""
    for key, value in sorted(env.items()):
        src = src.replace('${%s}' % key, value)
    return src