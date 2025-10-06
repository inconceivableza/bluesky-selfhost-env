#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

show_heading "Running docker logs" "$@"

{ docker compose logs "$@" ; DL_PID=$? ; } | { ./selfhost_scripts/log_formatter.py ; LF_PID=$? ; } &

# send interrupts to both parts of the pipe
trap "kill -INT $DL_PID $LF_PID 2>/dev/null; exit" SIGINT SIGTERM

wait $DL_PID $LF_PID

