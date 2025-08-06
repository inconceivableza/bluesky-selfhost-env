#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

cd "$script_dir"

show_heading "Checking for missing params" "in environment"
python "$script_dir"/ops-helper/check-env.py || { show_error "Missing params:" "please correct" ; exit 1 ;}

show_heading "Checking secrets configuration"
python "$script_dir"/ops-helper/check-secrets.py || { show_error "Secrets issues:" "please review and correct" ; exit 1 ;}

source_env

show_heading "Showing configuration"
make echo

show_heading "Generating secrets"
make genSecrets secret-envs

