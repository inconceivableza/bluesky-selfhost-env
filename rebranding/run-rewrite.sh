#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
commit_parts=0
[[ "$1" == "--commit-parts" ]] && {
    commit_parts=1
    shift
}
check_only=0
[[ "$1" == "--check-only" ]] && {
    check_only=1
    shift
}
keep_going=0
[[ "$1" == "--keep-going" || "$1" == "-k" ]] && {
    keep_going=1
    shift
}
BRAND_CONFIG_DIR="$1"
REBRAND_TEMPLATE_DIR="$script_dir"/repo-rules
export MANUAL_REBRANDED_REPOS="$REBRANDED_REPOS"
. $script_dir/../utils.sh

main_rebranding_dir="$script_dir"
main_rebranding_rel="$(get_relative_path "$main_rebranding_dir")"
alt_rebranding_dir="$(realpath "$script_dir/../../rebranding")"
alt_rebranding_rel="$(get_relative_path "$alt_rebranding_dir")"

function show_subdirs_with_brand_config() {
  base_dir="$1"
  [ "$base_dir" = "" ] && base_dir=.
  ls $base_dir/*/{social-app,atproto}.yml 2>/dev/null | sed 's#/\(social-app\|atproto\).yml##' | sort -u
}

function show_subdirs_with_brand_images() {
  base_dir="$1"
  [ "$base_dir" = "" ] && base_dir=.
  ls $base_dir/*/*branding.svg 2>/dev/null | sed 's#/[^/]*branding.svg##' | sort -u
}

function usage() {
    echo syntax "$0" "[--commit-parts|--check-only] [-k|--keep-going] brand_config_dir" >&2
    echo defined brand config dirs may include: `ls */*branding.svg 2>/dev/null | sed 's#/.*branding.svg##' | sort -u`
    echo "  "`show_subdirs_with_brand_images "$main_rebranding_rel"`
    [ -d "$main_rebranding_rel" ] && echo "  "`show_subdirs_with_brand_images "$alt_rebranding_rel"`
    echo to create a new one, copy opensky and adjust for your images
}

[[ "$1" == "-h" || "$1" == "--help" || "$BRAND_CONFIG_DIR" == "" || "$commit_parts$check_only" == 11 ]] && {
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

BRAND_IMAGES_FILE=branding.svg

[ -f "$BRAND_CONFIG_DIR/$BRAND_IMAGES_FILE" ] || {
    show_error "Brand images not found" "in directory $BRAND_CONFIG_DIR under $BRAND_IMAGES_FILE"
    exit 1
}

[ -f "$BRAND_CONFIG_DIR/branding.json" ] || {
    show_error "Branding config not found" "in directory $BRAND_CONFIG_DIR under branding.json"
    show_info "Copy and adjust the template" "from $REBRAND_TEMPLATE_DIR/branding.example.json5"
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
      if [ -f ${REBRAND_TEMPLATE_DIR}/${branded_repo}-images.mustache.yml ]
      # this isn't working now that this is really a mustache template
      # if yq -e 'has("rename_paths") or has("copy_files") or has("svg_html_subst") or has("svg_tsx_subst")' ${REBRAND_TEMPLATE_DIR}/${branded_repo}-images.mustache.yml > /dev/null 2>&1
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
    repo_dir="$script_dir/../repos/${branded_repo}"
    [ -d "$repo_dir" ] || { echo could not find dir for $repo_dir - place at $repo_dir  >&2 ; exit 1 ; }
    if [ "$check_only" != 1 ]; then
      (cd "$repo_dir" ; git diff --exit-code --stat ) || { show_error "Local changes exist" "in $repo_dir so aborting; please commit / stash first" ; exit 1 ; }
    fi
    branding_part_failures=""
    for branding_plan in "check:hardcoded" "check:verbage" "change:change-ids" "change:styles" "change:images"
      do
        branding_action="${branding_plan%%:*}"
        [[ "$branding_action" != "check" && "$check_only" == 1 ]] && { echo skipping $branding_plan as only checking ; continue ; }
        branding_part="${branding_plan##*:}"
        branding_part_basename=${branded_repo}${branding_part:+-}${branding_part}
        [ -f ${REBRAND_TEMPLATE_DIR}/${branding_part_basename}.mustache.yml ] || { echo could not find ${branding_part_basename}.mustache.yml in ${REBRAND_TEMPLATE_DIR} >&2 ; continue ; }
        python ${script_dir}/generate_rules.py -c ${BRAND_CONFIG_DIR}/branding.json -e ${params_file} ${REBRAND_TEMPLATE_DIR}/${branding_part_basename}.mustache.yml ${BRAND_CONFIG_DIR}/${branding_part_basename}.yml
        BRANDING_PART_RULES=${BRAND_CONFIG_DIR}/${branding_part_basename}.yml
        if [ -f $BRANDING_PART_RULES ]
          then
            (
              cd "$repo_dir"
              show_heading --oneline "Applying ${branding_part:-(global)}" "changes to $branded_repo in $(basename "`pwd`") with $(basename ${BRAND_CONFIG_DIR})"
              if [ "$check_only" != 1 ]; then
                git diff --exit-code --stat || { show_error "Local changes exist" "so aborting; please commit / stash first" ; exit 1 ; }
                git reset --hard
              fi
              # we no longer do renames of files
              # python ${script_dir}/apply_files.py --config "${BRANDING_PART_RULES}" --env-file "$params_file" --env-file "$BRAND_TMP_ENV_FILE" --git-mv --action rename || { echo error running apply-files >&2 ; exit 1 ; }
              (
                # semgrep can't handle empty versions of these variables
                [ "$http_proxy" == "" ] && unset http_proxy
                [ "$https_proxy" == "" ] && unset https_proxy
                [ "$no_proxy" == "" ] && unset no_proxy
                if [[ $(yq '.rules // [] | length' "${BRANDING_PART_RULES}") -eq 0 ]]
                  then
                    show_info --oneline "No semgrep rules" "for branding part ${branding_part:-(global)} - not running"
                elif [ "$branding_action" == "check" ]
                  then
                    show_info "Running semgrep" "to check for things requiring changes"
                    semgrep scan --config "${BRANDING_PART_RULES}" --exclude="branding*.json" --exclude=".env*" --exclude="env-config*.json" --error || {
                      show_warning "intervention required" "semgrep found code needing changes..." >&2
                      [ "$keep_going" == "0" ] && exit 1
                    }
                elif [ "$branding_action" == "change" ]
                  then
                    show_info "Running semgrep" "to change things we can patch automatically"
                    semgrep scan --config "${BRANDING_PART_RULES}" -a --exclude="branding*.json" --exclude=".env*" --exclude="env-config*.json" || {
                      echo error running semgrep >&2
                      exit 1
                    }
                else
                    show_error "Unknown action ${branding_action}" "in plan ${branding_plan}"
                    exit 1
                fi
              ) || exit 1
              [ -f "google-services.json.example" ] && cp google-services.json.example google-services.json  # this is for social-app
              python ${script_dir}/apply_files.py --config "${BRANDING_PART_RULES}" --env-file "$params_file" --env-file "$BRAND_TMP_ENV_FILE" -a copy -a svg-html -a svg-tsx || { echo error running apply-files >&2 ; exit 1 ; }
              if [ "$commit_parts" == "1" ]
                then
                  show_info --oneline "Checking for changes" "for ${branding_part:-(global)}"
                  if ! git diff --exit-code --stat
                    then
                      git add -u # staging changes
                      npx lint-staged --concurrent false --allow-empty || { show_warning "Lint error" "will not commit changes" ; exit 1 ; }
                      if ! git diff --exit-code --stat; then
                        show_info --oneline "Lint fixups" "will be staged for commit as well"
                        git add -u # staging changes from lint
                      fi
                      if git diff --exit-code --stat --staged; then
                        show_info --oneline "Empty changes" "after lint fixup; will not commit"
                      else
                        show_info --oneline "Committing changes" "for ${branding_part:-(global)}"
                        git commit -m "Applied branding part ${branding_part:-(global)} from $(basename ${BRAND_CONFIG_DIR})" || { show_warning "Could not commit" "changes" ; }
                      fi
                    fi
                else
                  show_info --oneline "Showing changes" "for ${branding_part:-(global)}"
                  git diff
                fi
            ) || {
              if [ "$check_only" == 1 ]; then
                show_warning "Detected needed changes in ${branded_repo} under ${branding_part:-(global)}:" "examine above error messages and correct"
                branding_part_failures="$branding_part_failures ${branding_part:-(global)}"
              else
                show_error "Patching ${branded_repo} failed ${branding_part:-(global)}:" "examine above error messages and correct"
                exit 1
              fi
            }
          fi
      done
  done
[ "$check_only" == 1 ] && [ "$branding_part_failures" != "" ] && {
  show_error "Changes needed in ${branded_repo}:" $branding_part_failures
  exit 1
}

