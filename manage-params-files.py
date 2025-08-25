#!/usr/bin/env python3
"""
Manage environment parameter files for Bluesky self-hosting.

This script manages symbolic links to environment parameter files,
allowing easy switching between different configurations.
"""

import argparse
import os
import sys
import re
from pathlib import Path


def get_env_filename(profile):
    """Get the environment filename for a given profile."""
    if profile:
        return f".env.{profile}"
    return ".env"


def list_env_files():
    """List all available environment files."""
    env_files = list(Path.cwd().glob("*.env"))
    if env_files:
        print("Available environment files:")
        for env_file in sorted(env_files):
            if not env_file.name.startswith("."):
                print(f"  {env_file.name}")
    else:
        print("No .env files found in current directory")


def show_current_env(env_file):
    """Show the current environment file status."""
    if env_file.is_symlink():
        target = env_file.readlink()
        print(f"{env_file.name} -> {target}")
        return True
    elif env_file.exists():
        print(f"{env_file.name} (regular file)")
        return True
    else:
        print(f"No {env_file.name} file found.")
        return False


def delete_env_link(env_file):
    """Delete the environment symlink."""
    if env_file.is_symlink():
        target = env_file.readlink()
        print(f"{env_file.name} was previously pointing to {target}")
        env_file.unlink()
        print("Removed symlink")
        return True
    elif env_file.exists():
        print(f"Error: {env_file.name} is not a symlink: not removing, check and adjust manually")
        os.system(f"ls -l {env_file}")
        return False
    else:
        print(f"No {env_file.name} found", file=sys.stderr)
        return False


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


def validate_profile(profile):
    """Validate profile name contains only allowed characters."""
    if not re.match(r'^[a-zA-Z0-9_.+-]+$', profile):
        print(f"Error: Invalid profile name '{profile}'. Only [a-zA-Z0-9_.+-] characters are allowed.", file=sys.stderr)
        return False
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Manage environment parameter files for Bluesky self-hosting",
        epilog="Examples:\n"
               "  %(prog)s                           # Show current .env status\n"
               "  %(prog)s myproject.env             # Link .env to myproject.env\n"
               "  %(prog)s -d                        # Delete current .env symlink\n"
               "  %(prog)s -p prod myproject.env     # Link .env.prod to myproject.env\n"
               "  %(prog)s --staging staging.env     # Link .env.staging to staging.env\n",
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

    profile_group = parser.add_mutually_exclusive_group()
    profile_group.add_argument(
        '-p', '--profile',
        help='Target profile for .env.{profile} (allows [a-zA-Z0-9_.+-] characters)'
    )
    profile_group.add_argument(
        '-P', '--prod',
        action='store_const',
        const='production',
        dest='profile',
        help='Shortcut for --profile production'
    )
    profile_group.add_argument(
        '-S', '--staging',
        action='store_const',
        const='staging',
        dest='profile',
        help='Shortcut for --profile staging'
    )

    args = parser.parse_args()

    # Change to script directory
    script_dir = Path(__file__).parent
    os.chdir(script_dir)

    # Validate profile if provided
    if args.profile and not validate_profile(args.profile):
        sys.exit(1)

    # Determine target environment file
    env_file = Path(get_env_filename(args.profile))

    # Handle delete operation
    if args.delete:
        success = delete_env_link(env_file)
        sys.exit(0 if success else 1)

    # Handle showing current status
    if not args.params_file:
        if show_current_env(env_file):
            sys.exit(0)
        else:
            print("Set by running this script with a parameters file. Potential options:", file=sys.stderr)
            list_env_files()
            sys.exit(1)

    # Handle creating new symlink
    success = create_env_link(args.params_file, env_file)
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()