#!/usr/bin/env bash

script_path="$(realpath "$0")"
script_dir="$(dirname "$script_path")"
script_name="${0##*/}"
. "$script_dir/utils-logging.sh"

named_target=
argselected_target=1
target_args_usage="-a|--android|-i|--ios "

[ "${script_name/android/}" != "$script_name" ] && named_target=android
[ "${script_name/ios/}" != "$script_name" ] && named_target=ios
[ "$named_target" != "" ] && { argselected_target= ; target_args_usage= ; }

intl_target=build
# default is to increment expected build_number, but this can be overridden by running with build_number_increment=0
[ "$build_number_increment" == "" ] && build_number_increment=1
set_build_number=
set_bundle_version=1

function show_usage() {
  echo "Syntax $0 [-?|-h|--help] ${target_args_usage}[-k|--keep-tmp] [--intl={build|compile|}|--no-intl] [build_profile [env_profile]]"
}

function get_build_profiles() {
  jq -r '.build | keys[]' "$script_dir/repos/social-app/eas.json" | grep -v base
}

function query_eas_profile() {
  jq -r '.build."'${build_profile}'"'"$1" "$script_dir/repos/social-app/eas.json"
}

function show_help() {
  echo "Usage: $0 ${target_args_usage}[-k|--keep-tmp] [--intl={build|compile|}|--no-intl] [build_profile [env_profile]]"
  echo
  if [ "$named_target" != "" ]; then
    echo "Build the social-app for $named_target"
  else
    echo "Build the social-app for mobile"
  fi
  echo
  echo "Options:"
  echo "  -K, --keep-error    doesn't remove the temporary directory that the expo build runs in, if there's an error"
  echo "  -k, --keep-tmp      doesn't remove the temporary directory that the expo build runs in, even on success"
  echo "  --set-buildno=N     updates the eas build servers to set build number to N (build will be N+1)"
  echo "  --set-bundlever     writes build_number into CFBundleVersion in the main app's Info.plist [ios] (default)"
  echo "  --no-set-bundlever  doesn't write build_number into CFBundleVersion in the main app's Info.plist [ios]"
  echo "  --ignore-bundlever  ignores mismatch between build_number and CFBundleVersion in the main app's Info.plist [ios]"
  echo "  --no-intl           skips yarn intl: preparation"
  echo "  --intl=TARGET       runs yarn intl:build or intl:compile or skips if missing (default build)"
  [ "$argselected_target" == 1 ] && {
    echo "  -a, --android       targets android build"
    echo "  -i, --ios           targets ios build"
  }
  echo "  build_profile       name of the expo build profile for android - defaults to development"
  echo "                      options: "$(get_build_profiles)
  echo "  env_profile         name of the env-config to use by default - for non-production, can be selected at runtime."
  echo "                      defaults to the build_profile's corresponding environment, with testflight*/preview* -> test"
  echo "                      options: development test production"
  echo
}

keep_tmp=
build_profile=
selfhost_env_profile=
target_os="$named_target"

while [ "$#" -gt 0 ]
  do
    [[ "$1" == "-k" || "$1" == "--keep-tmp" ]] && { keep_tmp=1 ; shift 1 ; continue ; }
    [[ "$1" == "-K" || "$1" == "--keep-error" ]] && { keep_tmp=error ; shift 1 ; continue ; }
    [[ "$1" == "--no-build-incr" ]] && { build_number_increment=0 ; shift 1 ; continue ; }
    [[ "$1" == "--build-incr" ]] && { build_number_increment=1 ; shift 1 ; continue ; }
    [[ "${1#--set-build-no=}" != "$1" ]] && { set_build_number="${1#--set-build-no=}" ; shift 1 ; continue ; }
    [[ "$1" == "--set-buildno" ]] && { shift 1 ; set_build_number="$1" ; shift 1 ; continue ; }
    [[ "$1" == "--set-bundlever" ]] && { set_bundle_version=1 ; shift 1 ; continue ; }
    [[ "$1" == "--no-set-bundlever" ]] && { set_bundle_version=0 ; shift 1 ; continue ; }
    [[ "$1" == "--ignore-bundlever" ]] && { set_bundle_version=ignore ; shift 1 ; continue ; }
    [[ "$1" == "-a" || "$1" == "--android" ]] && {
      [[ "$target_os" != "" && "$target_os" != "android" ]] && { show_error "Target configured" "but already targetting $target_os - $1 not valid" ; show_usage 1 ; exit ; }
      target_os="android" ; shift 1 ; continue
    }
    [[ "$1" == "-i" || "$1" == "--ios" ]] && {
      [[ "$target_os" != "" && "$target_os" != "ios" ]] && { show_error "Target configured" "but already targetting $target_os - $1 not valid" ; show_usage 1 ; exit ; }
      target_os="ios" ; shift 1 ; continue
    }
    [[ "${1#--intl=}" != "$1" ]] && { intl_target="${1#--intl=}" ; shift 1 ; continue ; }
    [[ "${1}" == "--no-intl" ]] && { intl_target= ; shift 1 ; continue ; }
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

[ "$target_os" == "" ] && { show_error "Mobile target required" "specify android or ios with flags" ; show_usage ; exit 1 ; }
[ "$target_os" != "$named_target" ] && show_info --oneline "Selected mobile target" "$target_os"
target_os_name="$target_os"
[ "$target_os" == "android" ] && target_os_name="Android"
[ "$target_os" == "ios" ] && target_os_name="iOS"

[ "$build_profile" == "" ] && build_profile="development"

if [ "$selfhost_env_profile" == "" ]
  then
    selfhost_env_profile="$build_profile"
    [[ "${selfhost_env_profile#testflight}" != "$selfhost_env_profile" || "${selfhost_env_profile#preview}" != "$selfhost_env_profile" ]] && selfhost_env_profile=test
    [[ "${selfhost_env_profile#development}" != "$selfhost_env_profile" ]] && selfhost_env_profile=development
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

show_heading "Building ${target_os_name} app" "using applied branding, ${build_profile} profile and ${selfhost_env_profile} default environment"

[ "$target_os" == "android" ] && {
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
}

cd "$script_dir/repos/social-app"

which nvm || . ~/.nvm/nvm.sh
nvm use 20

function get_expected_extension() {
  [ "$target_os" == "ios" ] && {
    forSimulator="$(query_eas_profile ".ios.simulator")"
    [ "$forSimulator" == "true" ] && { echo tgz ; return 0 ; }
    echo ipa ; return 0
  }
  # based on https://docs.expo.dev/build-reference/apk/
  devClient="$(jq -r .build.${build_profile}.developmentClient eas.json)"
  dist="$(jq -r .build.${build_profile}.distribution eas.json)"
  buildType="$(jq -r .build.${build_profile}.android.buildType eas.json)"
  gradCmd="$(jq -r .build.${build_profile}.android.gradleCommand eas.json)"
  [ "$buildType" != "" ] && [ "$buildType" != null ] && { echo "$buildType" ; return 0; }
  [ "$gradCmd" != "" ] && [ "$gradCmd" != null ] && { show_warning "Cannot determine extension" "profile $build_profile has gradle command configured" ; return 1 ; }
  if [ "$dist" == "internal" ] || [ "$devClient" == "true" ]
    then
      echo apk
      return 0
    fi
  echo aab
}

show_heading "Determining build info" "to set filename etc"
build_flavour="${build_profile}"
build_name="$(jq -r .name package.json)"
build_version="$(jq -r .version package.json)"
[ "$set_build_number" != "" ] && {
  show_info --oneline "Updating remote build number" "to ${set_build_number}"
  $script_dir/selfhost_scripts/set-eas-build-number.expects "$set_build_number"
}
current_build_number=$(npx eas-cli build:version:get -p "$target_os" -e "$build_profile" --non-interactive --json | jq -r '.[]')
build_date="$(date +%Y%m%d)"
build_timestamp="$(date +%H%M%S)"
output_dir="$script_dir/tmp-builds/${target_os}-${build_name}-${build_version}-${build_date}-${build_timestamp}"
build_id="${build_name}-${build_version}-${build_flavour}-${build_date}-${build_timestamp}"
target_ext=$(get_expected_extension)
[ "$target_ext" == "" ] && exit 1
target_dir="$script_dir/${target_os}-builds/"
build_file="$build_id.$target_ext"
# build_number contains the expected build number, as the expo build will increment from the current build number
build_number=$((current_build_number+build_number_increment))
show_info --oneline "Build number" "current ${current_build_number}, expecting to build ${build_number}"
[ "$target_os" == android ] && export BSKY_ANDROID_VERSION_CODE=${build_number}
[ "$target_os" == ios ] && export BSKY_IOS_BUILD_NUMBER=${build_number}
show_info --oneline "Expected build" "${build_file}"
show_info --oneline "Creating temporary build output directory" "at ${output_dir}"
mkdir -p "$output_dir"
mkdir -p "$target_dir"

"$script_dir"/generate-env-files.sh

function get_eas_build_base {
  [ -d "$TMPDIR"/eas-build-local-nodejs ] || mkdir "$TMPDIR"/eas-build-local-nodejs
  tmpfile="$(mktemp -t eas-build-local-nodejs/)"
  rm "$tmpfile"
  dirname "$tmpfile"
}

export EAS_LOCAL_BUILD_WORKINGDIR="$(get_eas_build_base)/$(uuidgen | tr A-F a-f)"
mkdir "$EAS_LOCAL_BUILD_WORKINGDIR"
export build_dir="$EAS_LOCAL_BUILD_WORKINGDIR"

if [ "$keep_tmp" == 1 ]; then
  show_info --oneline "Keeping temporary files" "for inspection after build - remove once finished:" "$build_dir"
  export EAS_LOCAL_BUILD_SKIP_CLEANUP=1
elif [ "$keep_tmp" == error ]; then
  show_info --oneline "Will keep temporary files" "for inspection after build if error:" "$build_dir"
  export EAS_LOCAL_BUILD_SKIP_CLEANUP=1
else
  show_info --oneline "Temporary build output directory" "$build_dir"
fi

function pre_exit {
  [ "$#" -gt 0 ] && show_error "$@"
  if [ "$keep_tmp" == 1 ]; then
    show_info --oneline "Kept temporary files" "for inspection after build - remove once finished"
    show_info --oneline "Build directory" "$build_dir"
  elif [ "$keep_tmp" == error ]; then
    if [ "$#" -gt 0 ]; then
      show_warning --oneline "Keeping temporary files" "for inspection after build error - remove once finished"
    else
      show_info --oneline "Removing temporary files" "for inspection after successful build"
      rm -fr "$build_dir" || show_warning --oneline "Error removing temporary files" "check $build_dir"
    fi
  fi
  [ -d "$build_dir" ] && {
    if [ -n "$(find "$build_dir" -maxdepth 0 -type d -empty 2>/dev/null)" ]; then
      show_info --oneline "Build directory" "$build_dir is empty - removing"
      rmdir "$build_dir"
    else
      show_info --oneline "Build directory" "$build_dir"
      du -hs "$build_dir"
    fi
  }
  [ -d "$output_dir" ] && {
    if [ -n "$(find "$output_dir" -maxdepth 0 -type d -empty 2>/dev/null)" ]; then
      show_info --oneline "Build output directory" "$output_dir is empty - removing"
      rmdir "$output_dir"
    else
      show_info --oneline "Build output directory" "$output_dir"
      du -hs "$output_dir"
    fi
  }
}

function interrupt_handler {
  show_warning --oneline "Interrupted" "you may need to clean up temporary directories manually"
  show_info --oneline "Build directory" "$build_dir"
  show_info --oneline "Build output directory" "$output_dir"
  show_error --oneline "Exiting after Ctrl-C"
  exit 1
}

trap interrupt_handler SIGINT

show_heading "Running yarn" "to ensure everything is installed"
nvm use 20
# we need yarn to install devDependencies even if NODE_ENV=production, to complete the intl steps; the final expo build won't do this
yarn --production=false --frozen-lockfile || { pre_exit --oneline "Error installing" "check yarn output" ; exit 1 ; }

if [ "$intl_target" == "" ]; then
  show_info --oneline "Skipping intl compilation" "as requested"
else
  if [ "$intl_target" == "build" ]; then
    show_heading --oneline "Building intl" "by extracting strings and compiling"
  elif [ "$intl_target" == "compile" ]; then
    show_heading --oneline "Preparing intl" "by extracting compiling"
  else
    show_heading --oneline "Preparing intl" "by custom intl:$intl_target script"
  fi
  yarn intl:"$intl_target" || { pre_exit --oneline "Error with intl" "check yarn output" ; exit 1 ; }
fi

show_heading "Running prebuild" "for profile $build_profile"

export EXPO_PUBLIC_ENV=${build_profile}
if yarn prebuild -p "$target_os"
  then
    show_info --oneline "Prebuild completed" "for profile $build_profile"
  else
    pre_exit "Prebuild failed" "for profile $build_profile"
    exit 1
  fi

[ "$target_os" == "ios" ] && {
  app_name="$(EXPO_PUBLIC_ENV=$build_profile $script_dir/selfhost_scripts/get-social-app-config.js | jq -r '.expo.name' | sed 's/[ ()]//g')"
  export module_info_filename="./ios/$app_name/Info.plist"
  show_info --oneline "Checking build number alignment" "for main and extension projects in $module_info_filename"
  [ -f "$module_info_filename" ] || {
    show_error --oneline "Could not find ios info" "looking in $module_info_filename in repos/social-app"
    exit 1
  }
  app_bundle_version="$(python3 -c 'import plistlib as pl, os
p = pl.load(open(os.getenv("module_info_filename"), "rb"), fmt=pl.FMT_XML)
print(p.get("CFBundleVersion"))')"
  [ "$app_bundle_version" != "$current_build_number" ] && {
    if [ "$set_bundle_version" == 1 ]; then
      show_warning "Mismatched build version" "repos/social-app/$module_info_filename has $app_bundle_version but expecting $build_number - overriding"
      cp $module_info_filename $module_info_filename.orig
      # write the current_build_number as expo will do an increment
      build_number=$current_build_number python3 -c 'import plistlib as pl, os
fn = os.getenv("module_info_filename")
bn = os.getenv("build_number")
p = pl.load(open(fn, "rb"), fmt=pl.FMT_XML)
p["CFBundleVersion"] = bn
xml = pl.dumps(p, fmt=pl.FMT_XML) # check before trying to write to file
pl.dump(p, open(fn, "wb"), fmt=pl.FMT_XML)'
      diff -u $module_info_filename.orig $module_info_filename
    elif [ "$set_bundle_version" == ignore ]; then
      show_warning "Mismatched build version" "repos/social-app/$module_info_filename has $app_bundle_version but expecting $current_build_number - but ignore flag set so not adjusting"
    else
      show_error "Mismatched build version" "repos/social-app/$module_info_filename has $app_bundle_version but expecting $current_build_number - please check and correct before continuing"
      exit 1
    fi
  }
}

show_heading "Running build" "for profile $build_profile to generate $build_file"

[ -d "$TMPDIR"/metro-cache/ ] && {
  # to avoid https://github.com/expo/expo/issues/40145 and the like
  show_info --oneline "Clearing metro cache" "to prevent obscure build errors"
  rm -r "$TMPDIR"/metro-cache/
}

if npx eas-cli build -p "${target_os}" --local -e "${build_profile}" --output="$output_dir/$build_file"
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
        [ -f "${app_name}.apks" ] && {
          backup_file="${app_name}-$(stat -t --format="%y" "${app_name}.apks" | cut -c 1-16 | sed 's/[- :]//g')".apks
          show_warning "Renaming intermediate file" "${app_name}.apks -> ${backup_file}"
          mv "${app_name}.apks" "${backup_file}"
          ls -l "${backup_file}"
        }
        show_info "Extracting apk" "and renaming to ${app_name}"
        # FIXME: this requires credentials to have been downloaded
        echo bundletool build-apks --bundle "$build_file" --output="${app_name}.apks" --mode=universal
        bundletool build-apks --bundle "$build_file" --output="${app_name}.apks" --mode=universal || { show_error "bundletool failing" "dumping env" ; export ; }
        ls -l "${app_name}.apks"
        unzip "${app_name}.apks" universal.apk
        rm "${app_name}.apks"
        mv universal.apk "${target_dir}/${build_id}.apk"
        touch -r "$build_file" "${target_dir}/${build_id}.apk"
        mv "${build_file}" "${target_dir}/${build_id}.aab"
      else
        show_info "Moving build file" "${build_file} to ${output_dir}"
        mv "${build_file}" "${target_dir}/${build_file}"
      fi
    show_info "Cleaning up tmp build output dir" "${output_dir}"
    cd "${target_dir}"
    rmdir "${output_dir}"
    show_info "${target_os_name} app build complete" "and available in ${target_dir}"
    ls -l "${build_id}".*
  else
    pre_exit "Error building ${target_os_name} app:" "see above for details"
    exit 1
  fi

pre_exit

