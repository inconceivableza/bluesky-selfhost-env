#!/usr/bin/env python3

import configparser
import re
from pathlib import Path

base_dir = Path(__file__).parent.parent

def get_env_filename(profile):
    """Get the environment filename for a given profile."""
    if profile:
        return f".env.{profile}"
    return ".env"

def get_profile_env_paths(profiles):
    """Get list of environment files from profile names, as Path objects."""
    env_files = []
    for profile in profiles:
        env_files.append(Path(get_env_filename(profile)))
    return env_files

def get_existing_profile_names():
    """Get names of existing profiles (without .env prefix)."""
    profile_files = get_all_env_paths()
    profiles = []
    for env_file in profile_files:
        if env_file.name == ".env":
            profiles.append(None)  # Default profile
        elif env_file.name.startswith(".env."):
            profiles.append(env_file.name[5:])  # Remove .env. prefix
    return profiles

def get_all_env_paths():
    """Get all .env profile files (.env, .env.*, etc.), as Path objects"""
    env_files = []
    cwd = Path.cwd()
    env_file = cwd / ".env"
    if env_file.exists():
        env_files.append(env_file)
    # Add all other .env.* files
    env_files.extend(cwd.glob(".env.*"))
    return sorted(env_files)

def validate_profile_name(profile):
    """Validate profile name contains only allowed characters."""
    if not re.match(r'^[a-zA-Z0-9_.+-]+$', profile):
        return False
    return True

def get_branding_filename():
    env_file_path = base_dir / Path(f".env.production")
    if not env_file_path.exists():
        print(f"Warning: Environment file {env_file_path} not found for production profile", file=sys.stderr)
        return None
    try:
        # Read environment with interpolation to resolve variables
        env_vars = read_env(str(env_file_path), interpolate=True)
    except Exception as e:
        print(f"Error reading environment file {env_file_path}: {e}", file=sys.stderr)
        return None
    rebranding_dir = env_vars['REBRANDING_DIR'].strip('"')
    rebranding_path = base_dir / Path(rebranding_dir)
    branding_file_path = rebranding_path / "branding.yml"
    if not branding_file_path.exists():
        print(f"Warning: Expected branding file {branding_file_path} does not exist", file=sys.stderr)
        return None
    return branding_file_path

def check_syntax_issues(filepath):
    """Check for syntax issues like trailing spaces that Docker Compose would read into variables"""
    syntax_issues = []
    
    try:
        with open(filepath, 'r') as f:
            for line_num, line in enumerate(f, 1):
                # Skip commented out lines entirely (optional values)
                if line.strip().startswith('#'):
                    continue
                
                # Check for lines with variable assignments
                if '=' in line:
                    # Get the part before any comment
                    line_before_comment = line.split('#')[0] if '#' in line else line
                    
                    # Remove newline but keep other whitespace to check for trailing spaces
                    line_no_newline = line_before_comment.rstrip('\n\r')
                    
                    # Check for trailing spaces (but not newlines)
                    if line_no_newline.rstrip() != line_no_newline:
                        # Extract the variable name for the error
                        var_name = line.split('=')[0].strip()
                        syntax_issues.append(f"Line {line_num}: Variable '{var_name}' has trailing spaces that will be included in the value")

                # check for variable fallback syntax issues
                matches = re.findall(r'\$\{[^}]+\}', line.strip())
                for match in matches:
                    fallback_match = re.match(r'\$\{([A-Za-z_][A-Za-z0-9_]*)(:?[=+?-])([^}]*)\}', match)
                    if fallback_match:
                        varname, fallback_syntax, _ = fallback_match.groups()
                        if fallback_syntax != ':-':
                            syntax_issues.append(f"Line {line_num}: Variable expansion for {varname} uses syntax {fallback_syntax} for fallback in {match}; " "switch to ${VARIABLE:-fallback}")
                    elif not re.match(r'\$\{[A-Za-z0-9_]+\}', match):
                        syntax_issues.append(f"Line {line_num}: invalid variable syntax {match}")
    except FileNotFoundError:
        pass
    
    return syntax_issues

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


