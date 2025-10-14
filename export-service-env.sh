#!/usr/bin/env bash

[ "$#" -lt 1 ] && { echo syntax $0 servicename >&2 ; exit 1 ; }
service_name=$1
docker compose config $service_name | yq -o json ".services.$service_name.environment" | jq -r 'to_entries[] | "\(.key)=\(.value)"'
