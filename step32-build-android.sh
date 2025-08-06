#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"
source_env

show_heading "Building Android app" "using applied branding and domain name changes"

if [ "$JAVA_HOME" == "" ] || [ ! -d "$JAVA_HOME" ]
  then
    show_error "Java not found:" "default JAVA_HOME in $params_file to point to zulu17 install"
    exit 1
  fi

if [ "$ANDROID_HOME" == "" ] || [ ! -d "$ANDROID_HOME" ]
  then
    show_error "Android Sdk not found:" "default ANDROID_HOME in $params_file to point to sdk install"
    exit 1
  fi

cd "$script_dir/repos/social-app"

which nvm || . ~/.nvm/nvm.sh
nvm use 20
yarn

if npx eas-cli build -p android --local
  then
    build_file="`ls --sort=time --time=mtime | grep "build-[0-9]*.aab" | head -n 1`"
    build_number="`echo "$build_file" | sed 's/build-\([0-9]*\).aab/\1/'`"
    build_name="`jq -r .name package.json`"
    build_version="`jq -r .version package.json`"
    build_date="`date +%Y-%m-%d`"
    build_id="${build_name}-${build_version}-${build_date}-${build_number}"
    show_heading "Build complete:" "presumed aab file is:"
    ls -l "$build_file"
    app_name="${REBRANDING_NAME:=bluesky}"
    [ -f ${app_name}.apks ] && {
      backup_file=${app_name}-"$(stat -t --format="%y" ${app_name}.apks | cut -c 1-16 | sed 's/[- :]//g')".apks
      show_warning "Renaming intermediate file" "${app_name}.apks -> ${backup_file}"
      mv ${app_name}.apks ${backup_file}
      ls -l ${backup_file}
    }
    show_info "Extracting apk" "and renaming to ${app_name}"
    bundletool build-apks --bundle $build_file --output=${app_name}.apks --mode=universal
    ls -l ${app_name}.apks
    unzip ${app_name}.apks universal.apk
    rm ${app_name}.apks
    mv universal.apk ${build_id}.apk
    touch -r $build_file ${build_id}.apk
    mv ${build_file} ${build_id}.aab
    show_info "Android app extracted"
    ls -l ${build_id}.apk ${build_id}.aab
  else
    show_error "Error building Android app:" "see above for details"
    exit 1
  fi

