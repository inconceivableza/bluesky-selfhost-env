#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

set -o allexport
. "$params_file"
set +o allexport

show_heading "Running docker logs" "$*"
make docker-compose-exec cmd="logs $*" | ./ops-helper/utils/log_formatter.py

