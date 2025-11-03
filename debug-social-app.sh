#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

$script_dir/generate-env-files.sh

show_heading "Running yarn in debug mode" "for social-app"

show_info --oneline "Checking Android home" "for launching in emulator"
check_android_home

cd "$script_dir/repos/social-app"

show_info --oneline "Running yarn install"
yarn
show_info --oneline "Running yarn start"
yarn start

