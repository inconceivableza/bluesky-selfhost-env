#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

[[ "$1" == "" ]] && { echo Syntax $0 service... >&2 ; exit 1 ; }

show_heading "Running docker down" "$*"
make docker-compose-exec cmd="down $*"
show_heading "Running docker up -d" "$*"
make docker-compose-exec cmd="up -d $*"

