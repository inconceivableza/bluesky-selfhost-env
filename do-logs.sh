#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

show_heading "Running docker logs" "$*"
make docker-compose-exec cmd="logs $*" | ./selfhost_scripts/log_formatter.py

