#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
BRAND_CONFIG_DIR="$1"
REBRAND_TEMPLATE_DIR="$script_dir"/repo-rules
export MANUAL_REBRANDED_REPOS="$REBRANDED_REPOS"
. $script_dir/../utils.sh

main_rebranding_dir="$script_dir"
main_rebranding_rel="$(realpath --relative-to="." "$main_rebranding_dir")"
alt_rebranding_dir="$(realpath "$script_dir/../../rebranding")"
alt_rebranding_rel="$(realpath --relative-to="." "$alt_rebranding_dir")"

function show_subdirs_with_brand_config() {
  base_dir="$1"
  [ "$base_dir" = "" ] && base_dir=.
  ls $base_dir/*/{social-app,atproto}.yml 2>/dev/null | sed 's#/\(social-app\|atproto\).yml##' | sort -u
}

function show_subdirs_with_brand_images() {
  base_dir="$1"
  [ "$base_dir" = "" ] && base_dir=.
  ls $base_dir/*/*-branding.svg 2>/dev/null | sed 's#/[^/]*-branding.svg##' | sort -u
}

function usage() {
    echo syntax "$0" brand_config_dir >&2
    echo defined brand config dirs may include: `ls */*-branding.svg 2>/dev/null | sed 's#/.*-branding.svg##' | sort -u`
    echo "  "`show_subdirs_with_brand_images "$main_rebranding_rel"`
    [ -d "$main_rebranding_rel" ] && echo "  "`show_subdirs_with_brand_images "$alt_rebranding_rel"`
    echo to create a new one, copy opensky and adjust for your images
}

[[ "$1" == "-h" || "$1" == "--help" || "$BRAND_CONFIG_DIR" == "" ]] && {
    usage
    exit 1
}
[ ! -d "$BRAND_CONFIG_DIR" ] && {
    show_error "Directory not found" "brand_config_dir: $BRAND_CONFIG_DIR"
    usage
    exit 1
}

BRAND_CONFIG_DIR="`cd "$BRAND_CONFIG_DIR" ; pwd`"

cd "$script_dir"

[ -f venv/bin/activate ] && . venv/bin/activate

BRAND_IMAGES_FILE="`basename "$BRAND_CONFIG_DIR"`-branding.svg" 

[ -f "$BRAND_CONFIG_DIR/$BRAND_IMAGES_FILE" ] || {
    show_error "Brand images not found" "in directory $BRAND_CONFIG_DIR under $BRAND_IMAGES_FILE"
    exit 1
}

[ -f "$BRAND_CONFIG_DIR/branding.yml" ] || {
    show_error "Branding config not found" "in directory $BRAND_CONFIG_DIR under branding.yml"
    show_info "Copy and adjust the template" "from $REBRAND_TEMPLATE_DIR/branding.yml.example"
    exit 1
}

if [ "$os" == "macos" ]
  then
    BRAND_TMP_ENV_FILE="`mktemp`"
  else
    BRAND_TMP_ENV_FILE="`mktemp --suffix=.env`"
  fi
echo "BRAND_CONFIG_DIR=${BRAND_CONFIG_DIR}" >> "$BRAND_TMP_ENV_FILE" 
echo "BRAND_IMAGES_DIR=${BRAND_CONFIG_DIR}" >> "$BRAND_TMP_ENV_FILE" 

[ -f "$params_file" ] && { set -a ; . "$params_file" ; set +a ; }
# this can be overridden from a parent script via command-line arguments
[ "$MANUAL_REBRANDED_REPOS" != "" ] && export REBRANDED_REPOS="$MANUAL_REBRANDED_REPOS"

function needs_images() {
  show_info "Checking whether images should be rebuilt" "for $REBRANDED_REPOS"
  for branded_repo in $REBRANDED_REPOS
    do
      if yq -e 'has("rename_paths") or has("copy_files") or has("svg_html_subst") or has("svg_tsx_subst")' ${REBRAND_TEMPLATE_DIR}/${branded_repo}.mustache.yml > /dev/null 2>&1
        then
          show_info "Image build required" "for $branded_repo"
          return 0
        fi
    done
  return 1
}

if needs_images
  then
    python $script_dir/export-brand-images.py $BRAND_CONFIG_DIR/$BRAND_IMAGES_FILE || { show_error "Error exporting images" "from $BRAND_CONFIG_DIR" ; exit 1 ; }
  fi

for branded_repo in $REBRANDED_REPOS
  do
    # generate the branding rules from the template
    [ -f ${REBRAND_TEMPLATE_DIR}/${branded_repo}.mustache.yml ] || { echo could not find ${branded_repo}.mustache.yml in ${REBRAND_TEMPLATE_DIR} >&2 ; exit 1 ; }
    python ${script_dir}/generate_rules.py -c ${BRAND_CONFIG_DIR}/branding.yml -e ${params_file} ${REBRAND_TEMPLATE_DIR}/${branded_repo}.mustache.yml ${BRAND_CONFIG_DIR}/${branded_repo}.yml
    [ -f ${BRAND_CONFIG_DIR}/${branded_repo}.yml ] || { echo could not find ${BRAND_CONFIG_DIR}/${branded_repo}.yml >&2 ; exit 1 ; }
    repo_dir="$script_dir/../repos/${branded_repo}"
    [ -d "$repo_dir" ] || { echo could not find dir for $repo_dir - place at $repo_dir  >&2 ; exit 1 ; }
    (
      cd "$repo_dir"
      echo patching $branded_repo in `pwd` with $(basename ${BRAND_CONFIG_DIR})
      git reset --hard
      python ${script_dir}/apply_files.py --config "$BRAND_CONFIG_DIR"/${branded_repo}.yml --env-file "$params_file" --env-file "$BRAND_TMP_ENV_FILE" --git-mv --action rename || { echo error running apply-files >&2 ; exit 1 ; }
      (
        # semgrep can't handle empty versions of these variables
        [ "$http_proxy" == "" ] && unset http_proxy
        [ "$https_proxy" == "" ] && unset https_proxy
        [ "$no_proxy" == "" ] && unset no_proxy
        semgrep scan --config ${BRAND_CONFIG_DIR}/${branded_repo}.yml -a || { echo error running semgrep >&2 ; exit 1 ; }
      ) || exit 1
      [ -f "google-services.json.example" ] && cp google-services.json.example google-services.json  # this is for social-app
      python ${script_dir}/apply_files.py --config "$BRAND_CONFIG_DIR"/${branded_repo}.yml --env-file "$params_file" --env-file "$BRAND_TMP_ENV_FILE" -a copy -a svg-html -a svg-tsx || { echo error running apply-files >&2 ; exit 1 ; }
      echo "app_name=${REBRANDING_NAME}" > branding.env
      git add branding.env
      # git diff
    ) || { show_error "Patching ${branded_repo} failed:" "examine above error messages and correct" ; exit 1 ; }
  done


