#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
if [ "$#" -eq 1 ]
  then
    build_profile="$1"
    selfhost_env_profile="$build_profile"
  else
    build_profile="development"
  fi
. "$script_dir/utils.sh"
source_env || exit 1

show_heading "Building Android app" "using applied branding and ${build_profile} profile"

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
build_dir="$script_dir/tmp-builds/android-${build_name}-${build_version}-${build_date}-${build_timestamp}"
build_id="${build_name}-${build_version}-${build_flavour}-${build_date}-${build_timestamp}"
target_ext=`get_expected_extension`
[ "$target_ext" == "" ] && exit 1
target_dir="$script_dir/android-builds/"
build_file="$build_id.$target_ext"
show_info --oneline "Expected build" "${build_file}"
show_info --oneline "Creating temporary build directory" "at ${build_dir}"
mkdir -p "$build_dir"
mkdir -p "$target_dir"

show_heading "Creating environments" "for social-app from ${build_profile} environment"
# TODO: work out what the mobile build actually does with the .env files; should we switch .env to .env.development and copy .env.$build_profile to .env just for mobile builds?
$script_dir/selfhost_scripts/generate-social-env.py -P -D || { show_error "Error generating social-app environment" "which is required for build" ; exit 1 ; }
$script_dir/selfhost_scripts/generate-social-env.py -S || show_warning "Error generating social-app staging environment" "so build will not contain it"

show_heading "Running yarn" "to ensure everything is installed"
yarn

show_heading "Running build" "for profile $build_profile to generate $build_file"
if npx eas-cli build -p android --local -e $build_profile --output="$build_dir/$build_file"
  then
    cd "$build_dir"
    if [ -f "$build_file" ]
      then
        show_heading "Build complete:" "output file is:"
        ls -l "$build_file"
      else
        show_error "Build complete but no build found" "in $build_dir/$build_file"
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
        show_info "Moving build file" "${build_file} to ${build_dir}"
        mv ${build_file} ${target_dir}/${build_file}
      fi
    show_info "Cleaning up tmp build dir" "${build_dir}"
    cd "${target_dir}"
    rmdir "${build_dir}"
    show_info "Android app build complete" "and available in ${target_dir}"
    ls -l ${build_id}.*
  else
    show_error "Error building Android app:" "see above for details"
    exit 1
  fi

