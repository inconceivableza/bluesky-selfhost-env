#!/usr/bin/env bash
# this is meant to be sourced from stepNN-*.sh and utils.sh

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
  oneline=
  [ "$1" == "--oneline" ] && { oneline=true ; shift 1 ; }
  [ "$oneline" == "true" ] || echo
  echo -n "$red_color""$start_bold"$1 "$clear_bold" >&2
  shift 1
  echo "$@""$clear_text" >&2
}

function show_warning {
  oneline=
  [ "$1" == "--oneline" ] && { oneline=true ; shift 1 ; }
  [ "$oneline" == "true" ] || echo
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

have_utils_logging=1