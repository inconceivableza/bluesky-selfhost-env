#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

cd "$script_dir"

show_heading "Generating secrets" "if any are missing"
$script_dir/config/gen-secrets.sh
make secret-envs

show_heading "Checking for missing params" "in environment"
"$script_dir"/selfhost_scripts/check-env.py || { show_error "Missing params:" "please correct" ; exit 1 ;}

show_heading "Checking secrets configuration"
"$script_dir"/selfhost_scripts/check-secrets.py || { show_error "Secrets issues:" "please review and correct" ; exit 1 ;}

source_env

show_heading "Showing configuration"
make echo

