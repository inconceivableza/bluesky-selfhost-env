#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"
source_env || exit 1

show_heading "Building Docker containers" "using applied branding"

if [ $# -gt 0 ]
  then
    cmdlineDirs="$@"
    show_info "Will only build services" $cmdlineDirs
    BUILD_SERVICES="$cmdlineDirs"
  else
    BUILD_SERVICES="$CUSTOM_SERVICES $REBRANDED_SERVICES"
  fi

repoDirs="`make echo | grep ^repoDirs: | sed 's/^repoDirs: //'`"
missingRepos="`for repoDir in ${repoDirs}; do [ -d "$repoDir" ] || echo $repoDir ; done`"
show_heading "Cloning source code" "from the different repositories"
make cloneAll

show_heading "Creating environments" "for social-app from production, development and test environments"
$script_dir/selfhost_scripts/generate-social-env.py -P -D || { show_error "Error generating social-app environment" "which is required for build" ; exit 1 ; }
$script_dir/selfhost_scripts/generate-social-env.py -T || show_warning "Error generating social-app test environment" "so build will not contain it"
$script_dir/selfhost_scripts/generate-google-services-json.py -PDTV || show_warning "Error generating google services for all build environments"

failures=""
for service in $BUILD_SERVICES
  do
    BUILD_ARGS=
    [ "$service" == "social-link" ] && BUILD_ARGS="--build-arg=LINK_VERSION=$(cd $script_dir/repos/social-app ; git log -1 --format=%H bskylink/) $BUILD_ARGS"
    [ "$service" == "social-card" ] && BUILD_ARGS="--build-arg=CARD_VERSION=$(cd $script_dir/repos/social-app ; git log -1 --format=%H bskyogcard/) $BUILD_ARGS"
    if [ "${REBRANDED_SERVICES/${service}/}" == "${REBRANDED_SERVICES}" ]
      then
        show_heading "Building $service" "without domain customizations"
        make build DOMAIN= f=./docker-compose-builder.yaml services=$service build_args="$BUILD_ARGS" || failures="$failures $service"
      else
        show_heading "Building $service" "customized for domains in env files"
        make build DOMAIN= f=./docker-compose-builder.yaml services=$service build_args="$BUILD_ARGS" || failures="$failures $service"
      fi
    # 1) build image, customized for domain
  done

if [ "$failures" != "" ]
  then
    show_error "Error building containers" "for$failures"
    exit 1
  fi
