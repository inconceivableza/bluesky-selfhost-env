#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
if [ "$#" -eq 1 ]
  then
    build_profile="$1"
    selfhost_env_profile="$build_profile"
  else
    build_profile="preview"
  fi
. "$script_dir/utils.sh"
source_env || exit 1

show_heading "Building iOS app" "using applied branding and ${build_profile} profile"

cd "$script_dir/repos/social-app"

which nvm || . ~/.nvm/nvm.sh
nvm use 20

show_heading "Determining build info" "to set filename etc"
build_flavour=${build_profile}
build_name="`jq -r .name package.json`"
build_version="`jq -r .version package.json`"
build_date="`date +%Y%m%d`"
build_timestamp="`date +%H%M%S`"
build_dir="$script_dir/tmp-builds/ios-${build_name}-${build_version}-${build_date}-${build_timestamp}"
build_id="${build_name}-${build_version}-${build_flavour}-${build_date}-${build_timestamp}"
build_file="$build_id.ipa"
target_dir="$script_dir/ios-builds/"
show_info --oneline "Expected build" "${build_file}"
show_info --oneline "Creating temporary build directory" "at ${build_dir}"
mkdir -p "$build_dir"
mkdir -p "$target_dir"

show_heading "Running yarn" "to ensure everything is installed"
yarn

# issues with versions (ran ~npx expo install --check`)
show_heading "Running expo install check" "to check everything is installed"
npx expo install --check

# issues with npx doctor (added things to package.json, but was this necessary?)

show_heading "Running build" "for profile $build_profile to generate $build_file"
if npx eas-cli build -p ios --local -e ${build_profile} --output="$build_dir"
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
    ls -l "$build_file"
    mv ${build_file} ${target_dir}/${build_id}.ipa
    show_info "Cleaning up tmp build dir" "${build_dir}"
    cd "${target_dir}"
    rmdir "${build_dir}"
    show_info "iOS app build complete" "and available in ${target_dir}"
    ls -l ${build_id}.ipa
  else
    show_error "Error building iOS app:" "see above for details"
    exit 1
  fi

