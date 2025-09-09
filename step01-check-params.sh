#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

cd "$script_dir"

show_heading "Generating secrets" "if any are missing"
$script_dir/config/gen-secrets.sh
make secret-envs

show_heading "Checking for missing params" "in all required environments"
"$script_dir"/selfhost_scripts/check-env.py -D -P || { show_error "Missing params:" "please correct" ; exit 1 ;}

show_heading "Checking for missing params" "in test environment (not required)"
"$script_dir"/selfhost_scripts/check-env.py -T || { show_warning "Missing params in test:" "better to correct at some point" ; }

show_heading "Checking for missing params" "in branding configuration"
"$script_dir"/selfhost_scripts/check-branding.py || { show_error "Missing branding config:" "please correct" ; exit 1 ;}

show_heading "Checking secrets configuration"
"$script_dir"/selfhost_scripts/check-secrets.py || { show_error "Secrets issues:" "please review and correct" ; exit 1 ;}

show_heading "Sourcing the environment" "to verify that it doesn't show any errors"
source_env

