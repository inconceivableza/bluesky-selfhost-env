#!/usr/bin/env bash
# this is meant to be sourced from stepNN-*.sh

selfhost_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$have_utils_logging" == 1 ] || . "$selfhost_dir/utils-logging.sh"

function source_env {
  # exports variables in the .env file (or profile env file if parameter given)  into the current context
  env_file="${params_file:-$script_dir/.env}"
  if [ "$#" -eq 1 ]
    then
      profile="$1"
      env_file="${script_dir}/.env.$profile"
  elif [ "$selfhost_env_profile" != "" ]
    then
      profile="$selfhost_env_profile"
      env_file="${script_dir}/.env.$selfhost_env_profile"
    fi
  [ -f "$env_file" ] || { show_error "Could not find env" "for profile ${profile:-(default)}" ; return 1 ; }
  set -o allexport
  . "$env_file"
  set +o allexport
}

function get_relative_path() {
    python3 -c "import os.path; print(os.path.relpath('$1', '${2:-.}'))"
}

function wait_for_container {
  container_name=$1
  compose_file=${2:-$script_dir/docker-compose.yaml}
  
  # might need to look up the name outside docker compose
  echo -n "Waiting for $container_name... "
  until [ "$(docker inspect -f {{.State.Running}} $(docker compose -f "$compose_file" ps --format '{{.Name}}' ${container_name} 2>/dev/null) 2>/dev/null)" == "true" ]
    do
      sleep 0.5
    done
  echo -n "started... "
  
  # Check if the service has a health check defined in the compose file
  if yq eval ".services.${container_name}.healthcheck // false" "$compose_file" >/dev/null 2>&1 && [ "$(yq eval ".services.${container_name}.healthcheck // false" "$compose_file")" != "false" ]; then
    # Container has health check, wait for it to be healthy
    until [ "$(docker inspect -f {{.State.Health.Status}} $(docker compose -f "$compose_file" ps --format '{{.Name}}' ${container_name} 2>/dev/null) 2>/dev/null)" == "healthy" ]
      do
        sleep 0.5;
      done
    echo -n "healthy... "
  else
    # Container has no health check, just wait a bit for it to be fully started
    sleep 1
    echo -n "ready... "
  fi
  
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

function potential_android_homes {
  if [ "$os" == "macos" ]
    then
      echo /opt/homebrew/share/android-commandlinetools
  elif [ "$os" == "linux" ]
    then
      echo "$HOME/Android/Sdk/"
  else
      show_warning "Could not determine potential android home" "for OS $os" >&2
  fi
}

function check_android_home {
  if [ "$ANDROID_HOME" == "" ]
    then
      for potential_android_home in $(potential_android_homes)
        do
          if [ "$potential_android_home" != "" ] && [ -d "$potential_android_home" ]
            then
              export ANDROID_HOME="$potential_android_home"
              echo $potential_android_home
              return 0
            fi
        done
      if [ "$ANDROID_HOME" == "" ]
        then
          show_error "Android Sdk not found:" "set ANDROID_HOME in $params_file to point to sdk install"
          return 1
        fi
  elif [ -d "$ANDROID_HOME" ]
    then
      return 0
  else
      show_error "Android Sdk not found:" "ANDROID_HOME in $params_file points to $ANDROID_HOME but it doesn't exist"
      return 1
  fi
}
function setup_python_venv_with_requirements {
  venv_target=venv
  [ -d $venv_target ] || python3 -m venv $venv_target
  . $venv_target/bin/activate || {
    show_error "Could not activate" "virtual environment in `realpath $venv_target`"
    return 1
  }
  [ "$(dirname $(which python))" == "$(realpath $venv_target/bin)" ] || {
    show_error "Malformed virtual environment" "in $(realpath $venv_target). Recreate manually"
    return 1
  }
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

if [ "$selfhost_env_profile" != "" ]
  then
    maybe_show_info --oneline "Self-host environment using profile" "$selfhost_env_profile"
    selfhost_env_filename=".env.${selfhost_env_profile}"
  else
    selfhost_env_filename=".env"
  fi

if [[ "$params_file" != "" && "$(realpath "$params_file")" != "$(realpath "$selfhost_dir/$selfhost_env_filename")" ]]
  then
    show_warning "Params file variable" "\$params_file is no longer supported; rather use ./params-file-util.sh to switch .env symlink"
    show_info "params_file was set to" "$params_file"
    export params_file="$selfhost_dir/$selfhost_env_filename"
    show_info "params_file reset to" "$params_file"
  else
    export params_file="$selfhost_dir/$selfhost_env_filename"
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

# DNS lookup function from step20-check-network.sh
if [ "$os" == "macos" ]
  then
    function dns_lookup() {
      if [ $# -ge 2 ]
        then
          dig +short -t a -q "$1" "@$2" | tail -n 1
        else
          echo dscacheutil >&2
          dscacheutil -q host -a name "$1" | grep 'ip_address:' | sed 's/^[a-z_]*: //' | tail -n 1
        fi
    }
  else
    function dns_lookup() {
      if [ $# -ge 2 ]
        then
          dig +short -t a -q "$1" "@$2" | tail -n 1
        else
          dig +short -t a -q "$1" | tail -n 1
        fi
    }
  fi

# Function to generate CA bundle files from root and intermediate certificates
function generate_ca_bundles() {
  local certs_dir="${1:-`pwd`/certs}"
  
  if [ -f "$certs_dir/root.crt" ] && [ -f "$certs_dir/intermediate.crt" ]; then
    # Create CA bundle for curl (intermediate first, then root)
    cat "$certs_dir/intermediate.crt" "$certs_dir/root.crt" > "$certs_dir/ca-bundle-curl.crt"
    # Create CA bundle for OpenSSL (root first, then intermediate) 
    cat "$certs_dir/root.crt" "$certs_dir/intermediate.crt" > "$certs_dir/ca-bundle-openssl.crt"
    echo "CA bundle files generated: ca-bundle-curl.crt, ca-bundle-openssl.crt"
  else
    echo "Warning: Cannot generate CA bundles - missing root.crt or intermediate.crt in $certs_dir"
    return 1
  fi
}

export bluesky_utils_imported=1

# our params file can override this to true if it is desired, but it messes with the scripting
export auto_watchlog=false
# these are things we currently aren't forking or patching - for ops/patch.mk. Uncomment if you want to adjust
# export _nofork="feed-generator ozone jetstream"
# export _nopatch="did-method-plc pds"
# these are the bluesky repositories we clone and use - no different from what's in the makefile
# export _nrepo="social-app/submodules/atproto indigo social-app ozone jetstream feed-generator did-method-plc"
export npm_config_yes=true # stop npx eas-cli from asking whether to install itself; see https://stackoverflow.com/a/69006263
# These can be overridden in the env file, but generally shouldn't be - they affect which things we branch for branding in which way
export REBRANDED_REPOS=social-app
export REBRANDED_SERVICES="social-app social-card social-embed social-link"
export CUSTOM_SERVICES="pds palomar plc bgs bsky backup opensearch jetstream ozone-standalone feed-generator"
