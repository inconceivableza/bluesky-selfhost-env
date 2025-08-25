#!/usr/bin/env python3
"""
Manage environment parameter files for Bluesky self-hosting.

This script manages symbolic links to environment parameter files,
allowing easy switching between different configurations.
"""

import argparse
import os
import sys
import types
from pathlib import Path

# making relative imports work without having to make this directory a Python package
__script_dir__ = os.path.dirname(os.path.abspath(__file__))
__package__ = os.path.basename(__script_dir__).replace('-', '_')
package_module = types.ModuleType(__package__)
package_module.__package__ = __package__
package_module.__path__ = [__script_dir__]
sys.modules[__package__] = package_module

from .selfhost_scripts.env_utils import get_all_env_paths, get_env_filename, get_profile_env_paths, get_existing_profile_names, validate_profile_name

def list_env_files():
    """List all available environment files with symlink targets."""
    param_files = list(Path.cwd().glob("*.env"))
    profile_files = get_all_env_paths()

    # Create mapping of target files to their profile links
    target_to_profiles = {}
    for profile_file in profile_files:
        if profile_file.is_symlink():
            target = profile_file.readlink()
            target_to_profiles.setdefault(target.name, []).append(profile_file.name)

    if param_files:
        print("Available environment files:")
        for env_file in sorted(param_files):
            if not env_file.name.startswith("."):
                line = f"  {env_file.name}"
                # Show which profiles point to this file
                if env_file.name in target_to_profiles:
                    profiles = ", ".join(sorted(target_to_profiles[env_file.name]))
                    line += f" (current target for {profiles})"
                print(line)
    else:
        print("No .env files found in current directory")


def show_current_env(profiles):
    """Show the current environment file status."""
    success = True
    for profile in profiles:
        env_file = Path(get_env_filename(profile))
        if env_file.is_symlink():
            target = env_file.readlink()
            print(f"{env_file.name} -> {target}")
        elif env_file.exists():
            print(f"{env_file.name} (regular file)")
        else:
            print(f"No {env_file.name} file found for {profile or 'default'} profile.")
            success = False
    return success


def delete_env_links(profiles):
    """Delete environment symlinks for specified profiles."""
    env_files = get_profile_env_paths(profiles)
    success = True

    for env_file in env_files:
        if env_file.is_symlink():
            target = env_file.readlink()
            print(f"{env_file.name} was previously pointing to {target}")
            env_file.unlink()
            print(f"Removed symlink {env_file.name}")
        elif env_file.exists():
            print(f"Warning: {env_file.name} is not a symlink: not removing, check and adjust manually")
            os.system(f"ls -l {env_file}")
            success = False
        else:
            print(f"No {env_file.name} found", file=sys.stderr)
            success = False

    return success


def create_env_link(params_file, env_file):
    """Create a symlink to the parameters file."""
    params_path = Path(params_file)

    # Check if the source file exists
    if not params_path.exists():
        print(f"Error: Cannot find {params_file} to use as new environment file", file=sys.stderr)
        return False

    # Handle existing .env file/link
    if env_file.is_symlink():
        target = env_file.readlink()
        print(f"{env_file.name} was previously pointing to {target}")
        env_file.unlink()
    elif env_file.exists():
        print(f"Error: {env_file.name} is not a symlink: not removing, check and adjust manually")
        os.system(f"ls -l {env_file}")
        return False

    # Create the symlink
    env_file.symlink_to(params_path)
    os.system(f"ls -l {env_file}")
    return True


def create_env_links(params_file, profiles):
    """Create symlinks for specified profiles to the parameters file."""
    params_path = Path(params_file)

    # Check if the source file exists
    if not params_path.exists():
        print(f"Error: Cannot find {params_file} to use as new environment file", file=sys.stderr)
        return False

    env_files = get_profile_env_paths(profiles)
    success = True

    for env_file in env_files:
        success = success and create_env_link(params_file, env_file)
    return success


def main():
    parser = argparse.ArgumentParser(
        description="Manage environment parameter files for Bluesky self-hosting",
        epilog="Examples:\n"
               "  %(prog)s                           # Show current .env status\n"
               "  %(prog)s myproject.env             # Link .env to myproject.env\n"
               "  %(prog)s -d                        # Delete current .env symlink\n"
               "  %(prog)s -p prod myproject.env     # Link .env.prod to myproject.env\n"
               "  %(prog)s -p prod -p staging proj.env # Link multiple profiles\n"
               "  %(prog)s --staging staging.env     # Link .env.staging to staging.env\n"
               "  %(prog)s -a myproject.env          # Link all existing profiles\n"
               "  %(prog)s -a -d                     # Delete all existing profiles\n",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        'params_file',
        nargs='?',
        help='Parameters file to link to (e.g., myproject.env)'
    )

    parser.add_argument(
        '-d', '--delete',
        action='store_true',
        help='Delete the current environment symlink'
    )

    parser.add_argument(
        '-p', '--profile',
        action='append',
        dest='profiles',
        default=[],
        help='Target profile for .env.{profile} (allows [a-zA-Z0-9_.+-] characters, can be used multiple times)'
    )
    parser.add_argument(
        '-D', '--default',
        action='append_const',
        const='default',
        dest='profiles',
        help='Shortcut for --profile default which targets the main .env file'
    )
    parser.add_argument(
        '-P', '--prod',
        action='append_const',
        const='production',
        dest='profiles',
        help='Shortcut for --profile production'
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
        help='Apply command to all existing .env* files'
    )

    args = parser.parse_args()

    # Change to script directory
    script_dir = Path(__file__).parent
    os.chdir(script_dir)

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

    # Handle delete operation
    if args.delete:
        success = delete_env_links(profiles)
        sys.exit(0 if success else 1)

    # Handle showing current status
    if args.params_file:
        # Handle creating new symlink
        if not create_env_links(args.params_file, profiles):
            sys.exit(1)
    else:
        if not show_current_env(profiles):
            print()
            print("Set missing environments by running this script with a parameters file. Potential options:", file=sys.stderr)
            list_env_files()
            sys.exit(1)


if __name__ == '__main__':
    main()