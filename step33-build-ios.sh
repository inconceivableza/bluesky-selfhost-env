#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

set -o allexport
. "$params_file"
set +o allexport

show_heading "Building iOS app" "using applied branding and domain name changes"

cd "$script_dir/repos/social-app"

which nvm || . ~/.nvm/nvm.sh
nvm use 20
yarn

# issues with versions (ran ~npx expo install --check`)
npx expo install --check

# issues with npx doctor (added things to package.json, but was this necessary?)



if npx eas-cli build -p ios --local -e preview
  then
    build_file="`ls --sort=time --time=mtime | grep "build-[0-9]*.ipa" | head -n 1`"
    build_number="`echo "$build_file" | sed 's/build-\([0-9]*\).ipa/\1/'`"
    build_name="`jq -r .name package.json`"
    build_version="`jq -r .version package.json`"
    build_id="${build_name}-${build_version}-${build_date}-${build_number}"
    show_heading "Build complete:" "presumed ipa file is:"
    ls -l "$build_file"
    mv ${build_file} ${build_id}.ipa
    show_info "iOS app renamed"
    ls -l ${build_id}.ipa
  else
    show_error "Error building iOS app:" "see above for details"
    exit 1
  fi

