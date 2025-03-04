#!/bin/bash
# this is meant to be sourced from stepNN-*.sh

clear_text=$(printf '\e[0m')
start_bold=$(printf '\e[1m')
clear_bold=$(printf '\e[22m')
start_italic=$(printf '\e[3m')
clear_italic=$(printf '\e[23m')
red_color=$(printf '\e[1;31m')
green_color=$(printf '\e[1;32m')
blue_color=$(printf '\e[1;34m')
purple_color=$(printf '\e[1;35m')
reset_color=$(printf '\e[1;0m')

function show_heading {
  echo
  echo -n "$blue_color""$start_bold"$1 "$clear_bold"
  shift 1
  echo "$@""$clear_text"
  echo
}

function show_info {
  echo
  echo -n "$start_italic"$1 "$clear_italic"
  shift 1
  echo "$@""$clear_text"
  echo
}

function show_error {
  echo -n "$red_color""$start_bold"$1 "$clear_bold" >&2
  shift 1
  echo "$@""$clear_text" >&2
}

function show_warning {
  echo -n "$purple_color""$start_bold"$1 "$clear_bold" >&2
  shift 1
  echo "$@""$clear_text" >&2
}

function show_success {
  echo "${green_color}OK${reset_color}"
}

function show_success_n {
  echo -n "${green_color}OK${reset_color}"
}

function show_failure {
  echo "${red_color}Fail${reset_color}"
}

function show_failure_n {
  echo -n "${red_color}Fail${reset_color}"
}

function wait_for_container {
  container_name=$1
  # might need to look up the name outside docker compose
  echo -n "Waiting for $container_name... "
  until [ "$(docker inspect -f {{.State.Running}} $(docker compose ps --format '{{.Name}}' ${container_name} 2>/dev/null) 2>/dev/null)" == "true" ]
    do
      sleep 0.5
    done
  echo -n "started... "
  until [ "$(docker inspect -f {{.State.Health.Status}} $(docker compose ps --format '{{.Name}}' ${container_name} 2>/dev/null) 2>/dev/null)" == "healthy" ]
    do
      sleep 0.5;
    done
  show_success
}

function get_linux_os {
  . /etc/os-release
  if [ "$ID" != "" ]
    then
      echo $ID
    else
      echo unknown
  fi
}

uname_os=$(uname)
if [ "$uname_os" == "Linux" ]
  then
    os=linux-$(get_linux_os)
elif [ "$uname_os" == "Darwin" ]
  then
    os=macos
else
    os=unknown
fi

function maybe_show_info {
  [ "$bluesky_utils_imported" == "" ] && show_info "$@"
}

maybe_show_info "OS detected" $os

if [ "$params_file" != "" ]
  then
    maybe_show_info "Custom Parameters File" "using environment variable: $params_file"
    export params_file="`realpath "$params_file"`"

elif [ "`basename "$script_dir"`" == "rebranding" ]
  then
    export params_file="`realpath "$script_dir/../bluesky-params.env"`"
  else
    export params_file="$script_dir/bluesky-params.env"
  fi

export bluesky_utils_imported=1

# this will quit the calling script
[ -f "$params_file" ] || {
  show_error "Params file not found:" "$params_file"
  show_info "Please supply one:" "set params_file to point to the filename if not bluesky-params.env; use bluesky-params.env.example as template. See README.md for further info"
  exit 1
}

# our params file can override this to true if it is desired, but it messes with the scripting
export auto_watchlog=false
# these are things we currently aren't patching - for ops/patch.mk
export _nopatch=did-method-plc pds
# these are the bluesky repositories we clone and use
export _nrepo="atproto indigo social-app ozone jetstream feed-generator did-method-plc pds"

