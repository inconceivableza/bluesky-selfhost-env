#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

./check-env-vars.sh

show_heading "Searching repos" "for URLs, DIDs, mentions of bsky"
make exec under=./repos/* cmd='git ls-files | grep -v -e __ -e .json$ | xargs grep -R -n -A3 -B3 -f /tmp/envs.txt | grep -A2 -B2 -e :// -e did: -e bsky'

show_heading "Searching repos" "for mentions of bsky domains"
make exec under=./repos/* cmd='git ls-files | grep -v -e /tests/ -e /__ -e Makefile -e ".yaml$" -e ".md$" -e ".sh$" -e ".json$" -e ".txt$" -e "_test.go$" | xargs grep -n -e bsky.social -e bsky.app -e bsky.network  -e bsky.dev'

show_heading "Creating table" "mapping environment and container to value from source and docker compose"
# create table showing { env x container => value } with selfhost_scripts script.
cat ./docker-compose-builder.yaml | ./selfhost_scripts/compose2envtable/venv/bin/python ./selfhost_scripts/compose2envtable/main.py -l /tmp/envs.txt -o ./docs/env-container-vals.xlsx
show_info "Table created" "in ./docs/env-container-val.xslx"

