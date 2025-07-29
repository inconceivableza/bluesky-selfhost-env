#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

set -o allexport
. "$params_file"
set +o allexport

echo command-line args $# $@
if [ $# -gt 0 ]
  then
    cmdlineDirs="$@"
    show_info "Will only build services" $cmdlineDirs
    REBRANDED_SERVICES="$cmdlineDirs"
  fi

repoDirs="`make echo | grep ^repoDirs: | sed 's/^repoDirs: //'`"
missingRepos="`for repoDir in ${repoDirs}; do [ -d "$repoDir" ] || echo $repoDir ; done`"
show_heading "Cloning source code" "from the different repositories"
make cloneAll

failures=""
for branded_service in $REBRANDED_SERVICES
  do
    show_heading "Building $branded_service" "customized for domain $DOMAIN"
    # 1) build image, customized for domain
    make build f=./docker-compose-builder.yaml services=$branded_service || failures="$failures $branded_service"
  done

if [ "$failures" != "" ]
  then
    show_error "Error building containers" "for$failures"
    exit 1
  fi

# show_heading "Building other images" "without domain customization"
# 2) build images with original
# make build DOMAIN= f=./docker-compose-builder.yaml 


