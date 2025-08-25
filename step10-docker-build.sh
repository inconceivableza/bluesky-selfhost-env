#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"
source_env

echo command-line args $# $@
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

show_heading "Creating environments" "for social-app from production, development and staging environments"
$script_dir/selfhost_scripts/generate-social-env.py -P -D || { show_error "Error generating social-app environment" "which is required for build" ; exit 1 ; }
$script_dir/selfhost_Scripts/generate-social-env.py -S || show_warning "Error generating social-app staging environment" "so build will not contain it"

failures=""
for service in $BUILD_SERVICES
  do
    EXTRA_ARGS=
    [ "$service" == "social-link" ] && EXTRA_ARGS="SOCIAL_LINK_VERSION=$(cd $script_dir/repos/social-app ; git log -1 --format=%H bskylink/) $EXTRA_ARGS"
    [ "$service" == "social-card" ] && EXTRA_ARGS="SOCIAL_CARD_VERSION=$(cd $script_dir/repos/social-app ; git log -1 --format=%H bskyogcard/) $EXTRA_ARGS"
    if [ "${REBRANDED_SERVICES/${service}/}" == "${REBRANDED_SERVICES}" ]
      then
        show_heading "Building $service" "without domain customizations"
        make build DOMAIN= f=./docker-compose-builder.yaml services=$service $EXTRA_ARGS || failures="$failures $service"
      else
        show_heading "Building $service" "customized for domain $DOMAIN"
        make build f=./docker-compose-builder.yaml services=$service $EXTRA_ARGS || failures="$failures $service"
      fi
    # 1) build image, customized for domain
  done

if [ "$failures" != "" ]
  then
    show_error "Error building containers" "for$failures"
    exit 1
  fi
