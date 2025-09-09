#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"
source_env

show_heading "Deploy jetstream container"
make docker-start-bsky-jetstream

# FIXME: wait for jetstream?


