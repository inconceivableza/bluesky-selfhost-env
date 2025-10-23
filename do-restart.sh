#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

[[ "$1" == "" ]] && { echo Syntax $0 service... >&2 ; exit 1 ; }
services="$(echo "$@" | sed 's/ /\n/g')"
selected_bsky=
restart_bsky=
[[ "$(echo "$services" | grep '^bsky$')" == "bsky" ]] && {
  show_info "Bsky service selected" "will restart after other services"
  selected_bsky=1
  services="$(echo "$services" | grep -v '^bsky$')"
}
[[ "$selected_bsky" != "1" &&"$(echo "$services" | grep '^\(caddy\|pds\)$')" != "" ]] && {
  bsky_running=$(docker compose ps -q bsky)
  if [ "$bsky_running" == "" ]
    then
      show_info "caddy or pds selected" "bsky would require a restart but isn't running in container"
      restart_bsky=manual
    else
      show_info "caddy or pds selected" "bsky will require a restart"
      restart_bsky=1
    fi
}
services="$(echo $services)"

show_heading "Running docker down" "$*"
make docker-compose-exec cmd="down $*"
[ "$services" != "" ] && {
  show_heading "Running docker up -d" $services
  make docker-compose-exec cmd="up -d $services"
}
if [ "$selected_bsky" == "1" ]
  then
    show_heading "Running docker up -d" bsky
    make docker-compose-exec cmd="up -d bsky"
elif [ "$restart_bsky" == "1" ]
  then
    show_heading "Running docker restart" bsky
    make docker-compose-exec cmd="restart bsky"
elif [ "$restart_bsky" == "manual" ]
  then
    show_warning "Restart bsky manually" "otherwise firehose connection dropping will cause profile errors"
fi

