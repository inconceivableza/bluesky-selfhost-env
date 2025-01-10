#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

cd "$script_dir"
[ -f $params_file ] || { show_error "Params file not found" at $params_file ; exit 1 ; }

set -o allexport
. "$params_file"
set +o allexport

show_heading "Backing up data" "from docker containers with persistent data"

make docker-compose-exec cmd='up backup'
# make docker-compose-exec cmd='down backup'


