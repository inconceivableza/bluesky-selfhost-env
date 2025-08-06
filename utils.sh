#!/bin/bash
# this is meant to be sourced from stepNN-*.sh

selfhost_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  oneline=
  [ "$1" == "--oneline" ] && { oneline=true ; shift 1 ; }
  [ "$oneline" == "true" ] || echo
  echo -n "$blue_color""$start_bold"$1 "$clear_bold"
  shift 1
  echo "$@""$clear_text"
  [ "$oneline" == "true" ] || echo
}

function show_info {
  oneline=
  [ "$1" == "--oneline" ] && { oneline=true ; shift 1 ; }
  [ "$oneline" == "true" ] || echo
  echo -n "$start_italic"$1 "$clear_italic"
  shift 1
  echo "$@""$clear_text"
  [ "$oneline" == "true" ] || echo
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

function get_input {
  echo -n "$blue_color$start_italic"$1 "$clear_italic$reset_color"
  shift 1
  read -r -p "$*$clear_text"
  echo "$REPLY"
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

function source_env {
  # exports variables in the .env file into the current context
  set -o allexport
  . "${params_file:-$script_dir/.env}"
  set +o allexport
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

function setup_python_venv_with_requirements {
  venv_target=venv
  [ -d $venv_target ] || python3 -m venv $venv_target
  . $venv_target/bin/activate
  python -m pip install -U pip | { grep -v "^Requirement already satisfied" ; true ; }
  python -m pip install -r requirements.txt | { grep -v "^Requirement already satisfied" ; true ; }
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

if [[ "$params_file" != "" && "$(realpath "$params_file")" != "$(realpath "$selfhost_dir/.env")" ]]
  then
    show_warning "Params file variable" "\$params_file is no longer supported; rather use ./params-file-util.sh to switch .env symlink"
    show_info "params_file was set to" "$params_file"
    export params_file="$selfhost_dir/.env"
    show_info "params_file reset to" "$params_file"
  else
    export params_file="$selfhost_dir/.env"
    if [ -h "$params_file" ]
      then
        actual_params_file="`readlink -f "$params_file"`"
        maybe_show_info "Effective Environment File" "$actual_params_file"
      fi
  fi

if [ ! -e "$params_file" ]
  then
    show_error "Environment File Missing" "should be in $params_file"
    # this will quit the calling script
    exit 1
  fi

export bluesky_utils_imported=1

# our params file can override this to true if it is desired, but it messes with the scripting
export auto_watchlog=false
# these are things we currently aren't patching - for ops/patch.mk. Uncomment if you want to adjust
# export _nopatch="did-method-plc pds"
# these are the bluesky repositories we clone and use - no different from what's in the makefile
# export _nrepo="atproto indigo social-app ozone jetstream feed-generator did-method-plc"
export npm_config_yes=true # stop npx eas-cli from asking whether to install itself; see https://stackoverflow.com/a/69006263
# These can be overridden in the env file, but generally shouldn't be - they affect which things we branch for branding in which way
export REBRANDED_REPOS=social-app
export REBRANDED_SERVICES=social-app
export CUSTOM_SERVICES="pds palomar plc bgs bsky"
