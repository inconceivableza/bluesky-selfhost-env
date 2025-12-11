#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

show_heading "Running docker logs" "$@"

docker compose logs "$@" | "$script_dir/selfhost_scripts/log_formatter.py" &

pids="$(jobs -p) $!"
# send interrupts to both parts of the pipe
trap "kill -INT $pids 2>/dev/null; exit" SIGINT SIGTERM

wait $pids
