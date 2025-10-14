#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

[[ "$1" == "" ]] && { echo Syntax $0 service... >&2 ; exit 1 ; }
services="$(echo "$@" | sed 's/ /\n/g')"
restart_bsky=
[[ "$(echo "$services" | grep '^bsky$')" == "bsky" ]] && {
  show_info "Bsky service selected" "will restart after other services"
  restart_bsky=1
  services="$(echo "$services" | grep -v '^bsky$')"
}
services="$(echo $services)"

show_heading "Running docker down" "$*"
make docker-compose-exec cmd="down $*"
[ "$services" != "" ] && {
  show_heading "Running docker up -d" $services
  make docker-compose-exec cmd="up -d $services"
}
[ "$restart_bsky" == "1" ] && {
  show_heading "Running docker up -d" bsky
  make docker-compose-exec cmd="up -d bsky"
}

