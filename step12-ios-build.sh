#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils-logging.sh"

# syntax $0 [build_profile] [env_profile]
if [ "$#" -eq 1 ]
  then
    build_profile="$1"
    selfhost_env_profile="$build_profile"
    [[ "$selfhost_env_profile" == "testflight" || "$selfhost_env_profile" == "preview" ]] && selfhost_env_profile=test
elif [ "$#" -eq 2 ]
  then
    build_profile="$1"
    selfhost_env_profile="$2"
    manually_set_env_profile=1
  else
    build_profile="development"
    selfhost_env_profile="$build_profile"
  fi
if [ ! -f "$script_dir/.env.$selfhost_env_profile" ]
  then
    [ "$selfhost_env_profile" == "production" ] && { show_error "cannot build production" "as .env.production is missing" ; exit 1 ; }
    [ "$manually_set_env_profile" == 1 ] && { show_error "cannot find environment" "$selfhost_env_profile was manually specified but .env.$selfhost_env_profile does not exist" ; exit 1 ; }
    show_warning "selecting development environment" for build profile $build_profile rather than $selfhost_env_profile, as .env.$selfhost_env_profile does not exist
    selfhost_env_profile="development"
  fi
. "$script_dir/utils.sh"
source_env "$selfhost_env_profile" || exit 1

show_heading "Building iOS app" "using applied branding, ${build_profile} profile and ${selfhost_env_profile} default environment"

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

show_heading "Creating environments" "for social-app from ${build_profile} environment"
# TODO: work out what the mobile build actually does with the .env files; should we switch .env to .env.development and copy .env.$build_profile to .env just for mobile builds?
$script_dir/selfhost_scripts/generate-social-env.py -P -D || { show_error "Error generating social-app environment" "which is required for build" ; exit 1 ; }
$script_dir/selfhost_scripts/generate-social-env.py -T || show_warning "Error generating social-app test environment" "so build will not contain it"
$script_dir/selfhost_scripts/generate-google-services-json.py -PDTV || show_warning "Error generating google services for all build environments"

show_heading "Running yarn" "to ensure everything is installed"
yarn

# issues with versions (ran ~npx expo install --check`)
show_heading "Running expo install check" "to check everything is installed"
npx expo install --check

# issues with npx doctor (added things to package.json, but was this necessary?)

show_heading "Running build" "for profile $build_profile to generate $build_file"
if npx eas-cli build -p ios --local -e ${build_profile} --output="$build_dir/$build_file"
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

