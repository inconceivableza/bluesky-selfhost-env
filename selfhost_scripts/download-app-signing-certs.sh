#!/bin/bash

script_path="$(realpath "$0")"
script_dir="$(dirname "$(dirname "$script_path")")"
script_name="${0##*/}"
. "$script_dir/utils-logging.sh"

named_target=
argselected_target=1
target_args_usage="-a|--android|-i|--ios "

[ "${script_name/android/}" != "$script_name" ] && named_target=android
[ "${script_name/ios/}" != "$script_name" ] && named_target=ios
[ "$named_target" != "" ] && { argselected_target= ; target_args_usage= ; }

function show_usage() {
  echo "Syntax $0 [-?|-h|--help] ${target_args_usage}[-k|--keep-tmp] [--intl={build|compile|}|--no-intl] [build_profile]"
}

function get_build_profiles() {
  jq -r '.build | keys[]' "$script_dir/repos/social-app/eas.json" | grep -v base
}

function query_eas_profile() {
  jq -r '.build."'${build_profile}'"'"$1" "$script_dir/repos/social-app/eas.json"
}

function show_help() {
  echo "Usage: $0 ${target_args_usage} [build_profile]"
  echo
  if [ "$named_target" != "" ]; then
    echo "Download app signing certificates for $named_target"
  else
    echo "Download app signing certificates for mobile"
  fi
  echo
  echo "Options:"
  [ "$argselected_target" == 1 ] && {
    echo "  -a, --android       targets android build"
    echo "  -i, --ios           targets ios build"
  }
  echo "  build_profile       name of the expo build profile for android - defaults to development"
  echo "                      options: "$(get_build_profiles)
  echo
}


while [ "$#" -gt 0 ]
  do
    [[ "$1" == "-a" || "$1" == "--android" ]] && {
      [[ "$target_os" != "" && "$target_os" != "android" ]] && { show_error "Target configured" "but already targetting $target_os - $1 not valid" ; show_usage 1 ; exit ; }
      target_os="android" ; shift 1 ; continue
    }
    [[ "$1" == "-i" || "$1" == "--ios" ]] && {
      [[ "$target_os" != "" && "$target_os" != "ios" ]] && { show_error "Target configured" "but already targetting $target_os - $1 not valid" ; show_usage 1 ; exit ; }
      target_os="ios" ; shift 1 ; continue
    }
    [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] && { show_help >&2 ; exit ; }
    [[ "${1#-}" != "$1" ]] && {
      show_error "Unknown parameter" "$1"
      show_usage >&2
      exit 1
    }
    [ "$build_profile" == "" ] && { build_profile="$1" ; shift 1 ; continue ; }
    show_error "Unexpected parameter" "$1"
    show_usage >&2
    exit 1
  done

[ "$target_os" == "" ] && { show_error "Specify target OS" "as android or ios" ; show_usage ; exit 1 ; }
[ "$build_profile" == "" ] && { show_error "Specify build profile" "as one of: " $(get_build_profiles) ; show_usage ; exit 1 ; }

[ "$target_os" == ios ] && { show_warning "This tool doesn't support iOS yet" "so hopefully you're fixing it up to do so" ; }

show_heading "Downloading credentials" "for $target_os and profile $build_profile"

cd "$script_dir/repos/social-app"

expo_project_owner="$(jq -r '.code.expo_project_owner' conf/branding.json | tr '[:upper:]' '[:lower:]')"
app_name="$(jq -r '.naming.app_name' conf/branding.json | tr '[:upper:]' '[:lower:]')"
expected_credentials_file="credentials.json"
expected_name="@${expo_project_owner}__${app_name}.jks"
target_credentials_file="certs/${app_name}-${target_os}-${build_profile}.json"
target_name="certs/${app_name}-${target_os}-${build_profile}.jks"
show_info "Using EAS credentials" "to download the app signing certificate into $target_name"

show_info --oneline "Select profile $build_profile" "when prompted by the app"
show_info --oneline "Then choose credentials.json" "(Upload/Download Credentials between EAS servers and your local json) from the menu"
show_info --oneline "Then choose Download" "credentials from EAS to credentials.json"
show_info --oneline "Then exit" "by pressing any key as instructed, then choosing Go back, then choosing Exit"

npx eas-cli credentials -p "$target_os"

show_info "Looking for credentials" "in $expected_credentials_file"
if [ -f "$expected_credentials_file" ]; then
  expected_name="$(jq -r '.android.keystore.keystorePath' "$expected_credentials_file")"
  show_info "Looking for downloaded keystore" "$expected_name"
  if [ -f "$expected_name" ]; then
    show_info --oneline "Found keystore" "$expected_name; moving to $target_name"
    mv "$expected_name" "$script_dir"/"$target_name"
  fi
  show_info --oneline "Found credentials" "in $expected_credentials_file; moving to $target_credentials_file and adjusting"
  jq ".android.keystore.keystorePath = \"$script_dir/$target_name\"" "$expected_credentials_file" > "$script_dir"/"$target_credentials_file"
  rm $expected_credentials_file
fi

