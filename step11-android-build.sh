#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils-logging.sh"

function show_usage() {
  echo "Syntax $0 [-?|-h|--help] [-k|--keep-tmp] [build_profile [env_profile]]"
}

function get_build_profiles() {
  jq -r '.build | keys[]' $script_dir/repos/social-app/eas.json | grep -v base
}

function show_help() {
  echo "Usage: $0 [-k|--keep-tmp] [build_profile [env_profile]]"
  echo
  echo "Build the social-app for android"
  echo
  echo "Options:"
  echo "  -k, --keep-tmp      doesn't remove the temporary directory that the expo build runs in"
  echo "  build_profile       name of the expo build profile for android - defaults to development"
  echo "                      options: "$(get_build_profiles)
  echo "  env_profile         name of the env-config to use by default - for non-production, can be selected at runtime."
  echo "                      defaults to the build_profile's corresponding environment, with testflight/preview -> test"
  echo "                      options: development test production"
  echo
}

keep_tmp=
build_profile=
selfhost_env_profile=

while [ "$#" -gt 0 ]
  do
    [[ "$1" == "-k" || "$1" == "--keep-tmp" ]] && { keep_tmp=1 ; shift 1 ; continue ; }
    [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] && { show_help >&2 ; exit ; }
    [[ "${1#-}" != "$1" ]] && {
      show_error "Unknown parameter" "$1"
      show_usage >&2
      exit 1
    }
    [ "$build_profile" == "" ] && { build_profile="$1" ; shift 1 ; continue ; }
    [ "$selfhost_env_profile" == "" ] && { selfhost_env_profile="$1" ; shift 1 ; continue ; }
    show_error "Unexpected parameter" "$1"
    show_usage >&2
    exit 1
  done

[ "$build_profile" == "" ] && build_profile="development"

if [ "$selfhost_env_profile" == "" ]
  then
    selfhost_env_profile="$build_profile"
    [[ "$selfhost_env_profile" == "testflight" || "$selfhost_env_profile" == "preview" ]] && selfhost_env_profile=test
  else
    manually_set_env_profile=1
  fi
if [ ! -f "$script_dir/.env.$selfhost_env_profile" ]
  then
    [ "$selfhost_env_profile" == "production" ] && { show_error "cannot build production" "as .env.production is missing" ; exit 1 ; }
    [ "$manually_set_env_profile" == 1 ] && { show_error "cannot find environment" "$selfhost_env_profile was manually specified but .env.$selfhost_env_profile does not exist" ; exit 1 ; }
    show_warning "selecting development environment" "for build profile $build_profile rather than $selfhost_env_profile, as .env.$selfhost_env_profile does not exist"
    selfhost_env_profile="development"
  fi
. "$script_dir/utils.sh"
source_env "$selfhost_env_profile" || exit 1

show_heading "Building Android app" "using applied branding, ${build_profile} profile and ${selfhost_env_profile} default environment"

if [ "$JAVA_HOME" == "" ] || [ ! -d "$JAVA_HOME" ]
  then
    if which java && java --version && java --version | grep Zulu17 >/dev/null
      then
        show_info "Default Java" "found and matches expected Zulu17 version"
        [ "$os" == "macos" ] && export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home
      else
        show_error "Java not found:" "set JAVA_HOME in $params_file to point to zulu17 install"
        exit 1
      fi
  fi

new_android_home=$(check_android_home) || exit 1
if [ "$new_android_home" != "" ]
  then
    export ANDROID_HOME="$new_android_home"
    show_info "Default Android SDK" "found at $ANDROID_HOME"
  fi

cd "$script_dir/repos/social-app"

which nvm || . ~/.nvm/nvm.sh
nvm use 20

function get_expected_extension() {
  # based on https://docs.expo.dev/build-reference/apk/
  devClient="`jq -r .build.${build_profile}.developmentClient eas.json`"
  dist="`jq -r .build.${build_profile}.distribution eas.json`"
  buildType="`jq -r .build.${build_profile}.android.buildType eas.json`"
  gradCmd="`jq -r .build.${build_profile}.android.gradleCommand eas.json`"
  [ "$buildType" != "" ] && [ "$buildType" != null ] && { echo $buildType ; return 0; }
  [ "$gradCmd" != "" ] && [ "$gradCmd" != null ] && { show_warning "Cannot determine extension" "profile $build_profile has gradle command configured" ; return 1 ; }
  if [ "$dist" == "internal" ] || [ "$devClient" == "true" ]
    then
      echo apk
      return 0
    fi
  echo aab
}

show_heading "Determining build info" "to set filename etc"
build_flavour=${build_profile}
build_name="`jq -r .name package.json`"
build_version="`jq -r .version package.json`"
build_date="`date +%Y%m%d`"
build_timestamp="`date +%H%M%S`"
output_dir="$script_dir/tmp-builds/android-${build_name}-${build_version}-${build_date}-${build_timestamp}"
build_id="${build_name}-${build_version}-${build_flavour}-${build_date}-${build_timestamp}"
target_ext=`get_expected_extension`
[ "$target_ext" == "" ] && exit 1
target_dir="$script_dir/android-builds/"
build_file="$build_id.$target_ext"
show_info --oneline "Expected build" "${build_file}"
show_info --oneline "Creating temporary build output directory" "at ${output_dir}"
mkdir -p "$output_dir"
mkdir -p "$target_dir"

show_heading "Creating environments" "for social-app from ${build_profile} environment"
# TODO: work out what the mobile build actually does with the .env files; should we switch .env to .env.development and copy .env.$build_profile to .env just for mobile builds?
$script_dir/selfhost_scripts/generate-social-env.py -P -D || { show_error "Error generating social-app environment" "which is required for build" ; exit 1 ; }
$script_dir/selfhost_scripts/generate-social-env.py -T || show_warning "Error generating social-app test environment" "so build will not contain it"
$script_dir/selfhost_scripts/generate-google-services-json.py -PDTV || show_warning "Error generating google services for all build environments"

function get_eas_build_base {
  tmpfile="$(mktemp -t eas-build-local-nodejs/)"
  rm "$tmpfile"
  echo "$(dirname "$tmpfile")"
}

export EAS_LOCAL_BUILD_WORKINGDIR="$(get_eas_build_base)/$(uuidgen | tr A-F a-f)"
mkdir "$EAS_LOCAL_BUILD_WORKINGDIR"
export build_dir="$EAS_LOCAL_BUILD_WORKINGDIR"

if [ "$keep_tmp" == 1 ]
  then
    show_info --oneline "Keeping temporary files" "for inspection after build - remove once finished:" $build_dir
    export EAS_LOCAL_BUILD_SKIP_CLEANUP=1
  else
    show_info --oneline "Temporary build output directory" $build_dir
  fi

function conditional_remove_atproto {
  [[ -d "$build_dir" && -d "$build_dir/atproto" && "$(cd $build_dir ; ls)" == "atproto" && "$keep_tmp" == "" ]] && {
    show_info --oneline "Cleaning up atproto" "from build directory as only item remaining"
    rm -r "$build_dir/atproto"
    rmdir "$build_dir"
  }
}

function pre_exit {
  [ "$#" -gt 0 ] && show_error "$@"
  if [ "$keep_tmp" == 1 ]
    then
      show_info --oneline "Kept temporary files" "for inspection after build - remove once finished"
      show_info --oneline "Build directory" "$build_dir"
    else
      conditional_remove_atproto
      show_info --oneline "Build directory" "$build_dir"
      du -hs "$build_dir"
      show_info --oneline "Build output directory" "$output_dir"
    fi
}

function interrupt_handler {
  show_warning --oneline "Interrupted" "you may need to clean up temporary directories manually"
  show_info --oneline "Build directory" "$build_dir"
  conditional_remove_atproto
  show_info --oneline "Build output directory" "$output_dir"
  show_error --oneline "Exiting after Ctrl-C"
  exit 1
}

trap interrupt_handler SIGINT

show_heading "Running yarn" "to ensure everything is installed"
nvm use 20
yarn || { pre_exit --oneline "Error installing" "check yarn output" ; exit 1 ; }

show_heading "Packaging atproto" "from src repo"
./scripts/pack-atproto-packages.sh

show_heading "Running build" "for profile $build_profile to generate $build_file"

if npx eas-cli build -p android --local -e ${build_profile} --output="$output_dir/$build_file"
  then
    cd "$output_dir"
    if [ -f "$build_file" ]
      then
        show_heading "Build complete:" "output file is:"
        ls -l "$build_file"
      else
        pre_exit "Build complete but no build found" "in $output_dir/$build_file"
        exit 1
      fi
    if [ "$target_ext" == "aab" ]
      then
        app_name="${REBRANDING_NAME:=bluesky}"
        [ -f ${app_name}.apks ] && {
          backup_file=${app_name}-"$(stat -t --format="%y" ${app_name}.apks | cut -c 1-16 | sed 's/[- :]//g')".apks
          show_warning "Renaming intermediate file" "${app_name}.apks -> ${backup_file}"
          mv ${app_name}.apks ${backup_file}
          ls -l ${backup_file}
        }
        show_info "Extracting apk" "and renaming to ${app_name}"
        echo bundletool build-apks --bundle $build_file --output=${app_name}.apks --mode=universal
        bundletool build-apks --bundle $build_file --output=${app_name}.apks --mode=universal || { show_error "bundletool failing" "dumping env" ; export ; }
        ls -l ${app_name}.apks
        unzip ${app_name}.apks universal.apk
        rm ${app_name}.apks
        mv universal.apk ${target_dir}/${build_id}.apk
        touch -r $build_file ${target_dir}/${build_id}.apk
        mv ${build_file} ${target_dir}/${build_id}.aab
      else
        show_info "Moving build file" "${build_file} to ${output_dir}"
        mv ${build_file} ${target_dir}/${build_file}
      fi
    show_info "Cleaning up tmp build output dir" "${output_dir}"
    cd "${target_dir}"
    rmdir "${output_dir}"
    show_info "Android app build complete" "and available in ${target_dir}"
    ls -l ${build_id}.*
  else
    pre_exit "Error building Android app:" "see above for details"
    exit 1
  fi

pre_exit

