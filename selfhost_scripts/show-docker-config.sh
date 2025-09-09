#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`/.."
. "$script_dir/utils.sh"

cd "$script_dir"
[ -f $params_file ] || { show_error "Params file not found" at $params_file ; exit 1 ; }

set -o allexport
. "$params_file"
set +o allexport

show_heading "Showing configuration"
make echo

show_heading "Showing docker compose config"
make docker-compose-exec cmd='config'

