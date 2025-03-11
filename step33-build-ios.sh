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
    show_heading "Build complete:" "what did it output?"
    # ls -l "$build_file"
    # app_name="${REBRANDING_NAME:=bluesky}"
  else
    show_error "Error building iOS app:" "see above for details"
    exit 1
  fi

