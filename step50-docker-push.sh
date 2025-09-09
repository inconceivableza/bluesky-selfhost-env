#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"
source_env

if [ $# -gt 0 ]
  then
    cmdlineDirs="$@"
    show_info "Will only publish services" $cmdlineDirs
    BUILT_SERVICES="$cmdlineDirs"
  else
    BUILT_SERVICES="$REBRANDED_SERVICES $CUSTOM_SERVICES"
  fi

echo Targetting $BUILT_SERVICES

repoDirs="`make echo | grep ^repoDirs: | sed 's/^repoDirs: //'`"
missingRepos="`for repoDir in ${repoDirs}; do [ -d "$repoDir" ] || echo $repoDir ; done`"

show_info "Querying docker" "for available images"
docker_images_json="$(docker image ls --format json)" || { echo Error listing docker images >&2 ; exit 1 ; }

failures=""
for built_service in $BUILT_SERVICES
  do
    image_name="$(yq ".services.$built_service.image" docker-compose-builder.yaml | sed 's#^[^/]*/##' | sed 's#:[^:]*$##' | sed 's#[$]{REBRANDING_NAME[^}]*}#'"${REBRANDING_NAME}#")"
    if [ "${REBRANDED_SERVICES/${built_service}/}" != "${REBRANDED_SERVICES}" ]
      then
        show_error "Domain-specific build" "of service $built_service for $REBRANDING_NAME and domain $DOMAIN - should not be tagged with domain"
        exit 1
        description="customized for $REBRANDING_NAME and domain $DOMAIN"
        json="$(echo "$docker_images_json" | jq "select(.Repository == \"$BRANDED_NAMESPACE/${image_name}\" and .Tag == \"$branded_asof-$DOMAIN\")")" || failures="$failures $built_service"
        target_name="$BRANDED_NAMESPACE/${image_name}:${branded_asof}-${DOMAIN}"
      else
        description="customized for $REBRANDING_NAME"
        json="$(echo "$docker_images_json" | jq "select(.Repository == \"$BRANDED_NAMESPACE/${image_name}\" and .Tag == \"$branded_asof\")")" || failures="$failures $built_service"
        target_name="$BRANDED_NAMESPACE/${image_name}:${branded_asof}"
      fi
      show_heading "Publishing $built_service" "$description to $target_name"
      function image_info() {
        echo "$json" | jq -r "$@"
      }
      show_info "Image details:" "created at $(image_info .CreatedAt) ($(image_info .CreatedSince)), size $(image_info .Size)"
      docker image push "$target_name"
  done

if [ "$failures" != "" ]
  then
    show_error "Error publishing containers" "for$failures"
    exit 1
  fi

# show_heading "Building other images" "without domain customization"
# 2) build images with original
# make build DOMAIN= f=./docker-compose-builder.yaml 


