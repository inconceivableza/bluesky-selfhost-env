#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"
source_env

cd "$script_dir"

show_heading "Backing up data" "from docker containers with persistent data"

make docker-compose-exec cmd='up backup'
# make docker-compose-exec cmd='down backup'


