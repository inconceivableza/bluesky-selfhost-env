#!/bin/sh
"exec" """""$(dirname $0)/venv/bin/python""""" "$0" "$@" # this is a shell exec which will drop down to the relative virtualenv's python

import argparse
import datetime
import logging
import os
from os.path import join
import shutil
import subprocess
import yaml
import replace_svg_in_tsx
import re
import sys

# Import from selfhost_scripts via requirements.txt link
from env_utils import read_env, replace_env

def rename_files(config, env, dry_run=False, git_mv=False):
    def get_config(node, key):
        value = node.get(key)
        return replace_env(value, env) if value else value
    for rename_config in config:
        src_path = get_config(rename_config, 'src_path')
        dest_path = get_config(rename_config, 'dest_path')
        if os.path.exists(dest_path):
            logging.error(f"Destination path {dest_path} already exists; rename will fail. Please select an appropriate option:")
            
            # Show detailed information about source and destination
            print(f"\nSource path info:")
            subprocess.run(["ls", "-ld", src_path])
            
            print(f"\nDestination path info:")
            subprocess.run(["ls", "-ld", dest_path])
            
            print(f"\nContents of destination directory:")
            if os.path.isdir(dest_path):
                subprocess.run(["ls", "-la", dest_path])
            else:
                print("(destination is not a directory)")
            
            # Prompt user for action
            while True:
                choice = input(f"\nDestination '{dest_path}' already exists. What would you like to do?\n"
                              f"  [b] Backup destination and continue\n"
                              f"  [r] Remove destination and continue\n"
                              f"  [c] Continue without removing (may cause errors)\n" 
                              f"  [q] Quit\n"
                              f"Choice (b/r/c/q): ").lower().strip()
                
                if choice == 'b':
                    dest_path_backup = os.path.join(os.path.dirname(dest_path), os.path.basename(dest_path) + f'-backup-{datetime.datetime.now().strftime("%Y%m%d-%H%M%S")}')
                    print(f"Rename to {dest_path_backup}")
                    try:
                        os.rename(dest_path, dest_path_backup)
                        print(f"Rename succeeded")
                    except Exception as e:
                        logging.error("Rename failed: aborting")
                        raise
                elif choice == 'r':
                    try:
                        shutil.rmtree(dest_path)
                        print(f"Removed {dest_path}")
                        break
                    except Exception as e:
                        print(f"Error removing {dest_path}: {e}")
                        continue
                elif choice == 'c':
                    print("Continuing without removing destination...")
                    break
                elif choice == 'q':
                    print("Quitting...")
                    sys.exit(1)
                else:
                    print("Invalid choice. Please enter 'b', 'r', 'c', or 'q'.")
        logging.info(f"Renaming {src_path} to {dest_path}")
        if not dry_run:
            if git_mv:
                subprocess.call(["git", "mv", src_path, dest_path])
            else:
                os.replace(src_path, dest_path)

def copy_files(config, env, dry_run=False):
    def get_config(node, key):
        value = node.get(key)
        return replace_env(value, env) if value else value
    for copy_config in config:
        src_dir = get_config(copy_config, 'src_dir')
        dest_dir = get_config(copy_config, 'dest_dir')
        copy_files = copy_config.get('files') or []
        do_git_add = copy_config.get('git_add', False)
        logging.info(f"Copying {len(copy_files)} files from {src_dir} to {dest_dir}")
        for filename_def in copy_files:
            filename = replace_env(filename_def, env)
            src_filename = join(src_dir, filename)
            dest_filename = join(dest_dir, filename)
            logging.info(f"Copying {filename}")
            if not dry_run:
                shutil.copy2(src_filename, dest_filename)
                if do_git_add:
                    subprocess.call(["git", "add", filename], cwd=dest_dir)

width_height_re = re.compile('width="[^"]*" height="[^"]*"')
view_box_re = re.compile('viewBox="[^"]*"')

def replace_svg_in_html_files(config, env, dry_run=False):
    def get_config(node, key, default=None):
        value = node.get(key, default)
        return replace_env(value, env) if value else value
    for subst_config in config:
        src_dir = get_config(subst_config, 'src_dir')
        dest_dir = get_config(subst_config, 'dest_dir')
        file_substs = subst_config.get('file_substs') or []
        logging.info(f"Substituting {len(file_substs)} files from {src_dir} to {dest_dir}")
        for file_subst_def in file_substs:
            src_filename = get_config(file_subst_def, 'dest')
            svg_filename = get_config(file_subst_def, 'src')
            view_box = get_config(file_subst_def, 'view_box')
            src_pathname = join(dest_dir, src_filename)
            svg_pathname = join(src_dir, svg_filename)
            logging.info(f"Substituting {svg_filename} into {src_filename}")
            with open(src_pathname) as f:
                src = f.read()
            with open(svg_pathname) as f:
                svg = f.read()
                if view_box:
                    for width_height in width_height_re.findall(svg):
                        svg = svg.replace(width_height, f'viewBox="{view_box}"')
            result = src[:src.find('<svg')] + svg + src[src.find('</svg>')+6:]
            if not dry_run:
                with open(src_pathname, 'w') as f:
                    f.write(result)

def replace_svg_in_tsx_files(config, env, dry_run=False):
    def get_config(node, key):
        value = node.get(key)
        return replace_env(value, env) if value else value
    for subst_config in config:
        src_dir = get_config(subst_config, 'src_dir')
        dest_dir = get_config(subst_config, 'dest_dir')
        file_substs = subst_config.get('file_substs') or []
        logging.info(f"Substituting {len(file_substs)} files from {src_dir} to {dest_dir}")
        for file_subst_def in file_substs:
            src_filename = get_config(file_subst_def, 'dest')
            svg_filename = get_config(file_subst_def, 'src')
            view_box = get_config(file_subst_def, 'view_box')
            pre_replace = file_subst_def.get('pre_replace', [])
            post_replace = file_subst_def.get('post_replace', [])
            src_pathname = join(dest_dir, src_filename)
            svg_pathname = join(src_dir, svg_filename)
            logging.info(f"Substituting {svg_filename} into {src_filename}")
            with open(src_pathname) as f:
                src = f.read()
            with open(svg_pathname) as f:
                svg = f.read()
            for pre_replace_def in pre_replace:
                find_re, repl = pre_replace_def['find'], pre_replace_def['replace']
                svg = re.sub(find_re, repl, svg)
            result = replace_svg_in_tsx.adjust_svg_and_import(src, svg)
            if view_box:
                for view_box_attr in view_box_re.findall(result):
                    result = result.replace(view_box_attr, f'viewBox="{view_box}"')
            for post_replace_def in post_replace:
                find_re, repl = post_replace_def['find'], post_replace_def['replace']
                result = re.sub(find_re, repl, result)
            if not dry_run:
                with open(src_pathname, 'w') as f:
                    f.write(result)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--config', type=str, required=True, help="Config file")
    parser.add_argument('-e', '--env-file', type=str, action='append', default=[], help="Env file (can specify multiple)")
    parser.add_argument('-n', '--dry-run', action='store_true', default=False, help="Don't actually copy")
    parser.add_argument('--git-mv', action='store_true', default=False, help="Do renames with git mv instead of mv")
    all_actions = ['rename', 'copy', 'svg-html', 'svg-tsx']
    parser.add_argument('-a', '--actions', action='append', choices=all_actions, default=[], help="Specify which actions to run (defaults to all)")
    parser.add_argument('-l', '--loglevel', type=str, default='INFO', help="log level")
    args = parser.parse_args()
    if args.loglevel:
        logging.getLogger().setLevel(args.loglevel)
    if not args.actions:
        args.actions = all_actions
    with open(args.config) as config_file:
        config = yaml.safe_load(config_file)
    env = {}
    for env_file in args.env_file:
        env.update(read_env(env_file))
    for action in args.actions:
        if action == 'rename':
            rename_files(config.get('rename_paths', []), env, dry_run=args.dry_run, git_mv=args.git_mv)
        elif action == 'copy':
            copy_files(config.get('copy_files', []), env, dry_run=args.dry_run)
        elif action == 'svg-html':
            replace_svg_in_html_files(config.get('svg_html_subst', []), env, dry_run=args.dry_run)
        elif action == 'svg-tsx':
            replace_svg_in_tsx_files(config.get('svg_tsx_subst', []), env, dry_run=args.dry_run)


