#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"
source_env || exit 1

function show_usage() {
  echo "Syntax $0 [-?|-h|--help] [service...]"
}

function show_help() {
  echo "Usage: $0 [-?|-h|--help] [service...]"
  echo
  echo "Build docker containers for services"
  echo
  echo "Options:"
  echo "  service             name of the service to build - defaults to all services"
  echo
}

show_heading "Building Docker containers" "using applied branding"

cmdlineDirs=""
while [ $# -gt 0 ]
  do
    [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] && { show_help >&2 ; exit ; }
    [[ "${1#-}" != "$1" ]] && {
      show_error "Unknown parameter" "$1"
      show_usage >&2
      exit 1
    }
    cmdlineDirs="$cmdlineDirs $1"
    shift 1
  done

if [ "${cmdlineDirs## }" == "" ]; then
  BUILD_SERVICES="$CUSTOM_SERVICES $REBRANDED_SERVICES"
else
  BUILD_SERVICES="${cmdlineDirs## }"
fi
show_info --oneline "Will build services" "$BUILD_SERVICES"

repoDirs="`make echo | grep ^repoDirs: | sed 's/^repoDirs: //'`"
missingRepos="`for repoDir in ${repoDirs}; do [ -d "$repoDir" ] || echo $repoDir ; done`"
show_heading "Cloning source code" "from the different repositories"
make cloneAll

$script_dir/generate-env-files.sh

function get_image_tag_varname() {
  service="$1"
  image_tag_def="$(yq -r ".services.${service}.image" $script_dir/docker-compose.yaml 2>/dev/null)"
  image_tag_varname="$(echo -n "$image_tag_def" | sed 's/^.*:[$][{]\([A-Z_]*IMAGE_TAG\).*$/\1/')"
  [ "$image_tag_varname" != "$image_tag_def" ] && echo -n "$image_tag_varname"
}

function is_git_commit() {
  image_tag_varname="$1"
  current_tag="${!image_tag_varname}"
  [ "$(echo -n "$current_tag" | wc -c)" == 40 ] && return 1
  return 0
}

function make_image_tag() {
  repodir="$1"
  cd $repodir
  git_commit=$(git log -1 --format=%H)
  hostname=$(hostname -s)
  image_tag="$git_commit-$hostname"
  git diff --ignore-submodules --exit-code --stat >/dev/null && image_tag="$image_tag-dirty"
  echo -n $image_tag
}

failures=""
for service in $BUILD_SERVICES
  do
    image_tag_varname="$(get_image_tag_varname "$service")"
    [ "$image_tag_varname" != "" ] && {
      original_image_tag="${!image_tag_varname}"
      service_dir="$script_dir/$(yq -r ".services.${service}.build.context" $script_dir/docker-compose.yaml 2>/dev/null)"
      [ -d "$service_dir" ] || { show_warning --oneline "Error finding build directory" "$service_dir" ; }
      is_git_commit "$image_tag_varname" && {
        export "$image_tag_varname"="$(make_image_tag "$service_dir")"
        show_warning --oneline "Changing docker image tag" "from $original_image_tag as it appears to be based on a git commit; will use current ${!image_tag_varname} instead"
      }
    }
    BUILD_ARGS=
    [ "$service" == "social-link" ] && BUILD_ARGS="--build-arg=LINK_VERSION=$(cd $script_dir/repos/social-app ; git log -1 --format=%H bskylink/) $BUILD_ARGS"
    [ "$service" == "social-card" ] && BUILD_ARGS="--build-arg=CARD_VERSION=$(cd $script_dir/repos/social-app ; git log -1 --format=%H bskyogcard/) $BUILD_ARGS"
    if [ "${REBRANDED_SERVICES/${service}/}" == "${REBRANDED_SERVICES}" ]
      then
        show_heading "Building $service" "without domain customizations"
        make build DOMAIN= f=./docker-compose.yaml services=$service build_args="$BUILD_ARGS" || failures="$failures $service"
      else
        show_heading "Building $service" "customized for domains in env files"
        make build DOMAIN= f=./docker-compose.yaml services=$service build_args="$BUILD_ARGS" || failures="$failures $service"
      fi
    # 1) build image, customized for domain
  done

if [ "$failures" != "" ]
  then
    show_error "Error building containers" "for$failures"
    exit 1
  fi
