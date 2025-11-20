#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

debug_config="$script_dir/debug-services.yaml"

function show_usage() {
  echo "Syntax $0 [-k|--keep-tmp] [-B|--skip-build] [-f|--format-logs] service"
}

function show_help() {
  echo "Usage: $0 [-k|--keep-tmp] [-B|--skip-build] [-f|--format-logs] service"
  echo
  echo "Runs a service directly on host, for quicker debugging, instead of in the docker container"
  echo
  echo "Options:"
  echo "  -k, --keep-tmp      doesn't remove the temporary directory that the script stores data in after running"
  echo "  -B, --skip-build    skips the build commands"
  echo "  -f, --format-logs   pipes the output through a log formatter"
  echo
  echo "Supported services:"
  for service in $(yq -oj -r ".services | keys() []" $debug_config)
    do
      echo "  ${service}"
    done
  echo
}

keep_tmp=
skip_build=
format_logs=

while [ "$#" -gt 0 ]
  do
    [[ "$1" == "-k" || "$1" == "--keep-tmp" ]] && { keep_tmp=1 ; shift 1 ; continue ; }
    [[ "$1" == "-B" || "$1" == "--skip-build" ]] && { skip_build=1 ; shift 1 ; continue ; }
    [[ "$1" == "-f" || "$1" == "--format-logs" ]] && { format_logs=1 ; shift 1 ; continue ; }
    [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] && { show_help >&2 ; exit ; }
    [[ "${1#/}" != "$1" ]] && {
      show_error "Unknown parameter" "$1"
      show_usage >&2
      exit 1
    }
    if [ "$service" == "" ]
      then
        service="$1"
        shift 1
      else
        show_error "Unexpected parameter" "$1"
        show_usage >&2
        exit 1
      fi
  done

[[ "$service" == "" ]] && { show_warning "service parameter is required" >&2 ; show_usage >&2 ; exit 1 ; }
service_present="$(yq -oj -r ".services | has(\"${service}\")" $debug_config)"

[ "$service_present" == "true" ] || { echo Service $service not found in $debug_config >&2 ; exit 1 ; }

show_heading "Running service $service" "$*"

service_json="$(yq -oj .services.${service} $debug_config)"

function jq_service() {
  echo "$service_json" | jq -r "$@"
}

function adopt_environment() {
  env_lines="$1"
  # exclude any excluded keys, plus those that will be overridden later
  env_lines="`echo "$env_lines" | grep -v "^export \($(jq_service '.env_exclude // [] + (.env_override // {} | keys_unsorted) | join("\\\\|")')\)="`"
  for subst in $(jq_service '.env_subst // [] | join ("\n")')
    do
      env_lines="$(echo "$env_lines" | sed "$subst")"
    done
  echo "$env_lines"
  for override in $(jq_service '.env_override | keys_unsorted[] as $k | "\($k)=\(.[$k])"')
    do
      echo "export ${override//\$script_dir/$script_dir/}"
    done
}

working_dir="$(jq_service .working_dir)"
cd $script_dir

running_env="$($script_dir/export-service-env.sh "$service" | sed 's#^#export #')"
build_commands="$(jq_service '.build[]')"
run_commands="$(jq_service '.run[]')"

# build commands are run in the normal environment

cd "$working_dir"
if [ "$skip_build" == 1 ]
  then
    show_info --oneline "Skipping build commands"
  else
    while IFS= read -r cmd
      do
        show_info --oneline "Running build command" "$cmd"
        $cmd || { show_warning --oneline "Error running build command" "please correct and rerun" ; exit 1 ; }
      done <<< "$build_commands"
  fi
 
cd $script_dir
cd "$working_dir"
export local_service_tmp_dir="`mktemp -d -t localdebug-$service`"

# run commands are run in the adopted environment
adopt_environment "$running_env" > "$local_service_tmp_dir/local-service-export.env"
(
  . "$local_service_tmp_dir/local-service-export.env"
  rm "$local_service_tmp_dir/local-service-export.env"
  set | grep ^PDS
  while IFS= read -r cmd
    do
      cmd="${cmd//\$local_service_tmp_dir/${local_service_tmp_dir/}}"
      show_info --oneline "Running command" "$cmd"
      $cmd | {
        if [ "$format_logs" == 1 ]
          then
            "$script_dir/selfhost_scripts/log_formatter.py" --no-json-prefix --default-service-prefix "$service"
          else
            cat
          fi
      }
      [ ${PIPESTATUS[0]} -ne 0 ] && { show_warning --oneline "Error running command" "please correct and rerun" ; break ; }
    done <<< "$run_commands"
)

if [ "$keep_tmp" == 1 ]
  then
    show_info --oneline "Keeping temporary directory" "$local_service_tmp_dir"
elif [ -d "$local_service_tmp_dir" ]
  then
    show_info --oneline "Removing temporary directory" "$local_service_tmp_dir"
    rm -r "$local_service_tmp_dir"
  fi

