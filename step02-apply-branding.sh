#!/bin/bash

# This patches the branded repositories based on the configured branding rules
# If you only want to apply it to particular repositories, pass them on the commandline

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"
source_env

repoDirs="`make echo | grep ^repoDirs: | sed 's/^repoDirs: //'`"
missingRepos="`for repoDir in ${repoDirs}; do [ -d "$repoDir" ] || echo $repoDir ; done`"
show_heading "Cloning source code" "from the different repositories"
make cloneAll

if [ $# -gt 0 ]
  then
    cmdlineDirs="$@"
    show_info "Will only run on repos" $cmdlineDirs
    repoDirs="$(for cmdlineDir in ${cmdlineDirs}; do echo $script_dir/repos/$cmdlineDir ; done)"
    REBRANDED_REPOS="$cmdlineDirs"
  fi

show_heading "Auto-creating latest work branch" "from the different repositories"
for repoDir in $repoDirs
  do
    (
      cd $repoDir
      echo "$blue_color$clear_bold`basename ${repoDir}`$reset_color"
      repo_branch_varname=$(basename $repoDir | sed 's/-/_/g')_branch
      src_branch=${!repo_branch_varname:-origin/main}
      [[ "$src_branch" != "origin/main" ]] && show_info "Using branch $src_branch" from \$$repo_branch_varname for repo $(basename $repoDir)
      $script_dir/autobranch.sh work $src_branch dockerbuild local-rebranding-$REBRANDING_NAME $src_branch main
    ) || { show_error "Error updating to latest branch:" "inspect $repoDir and adjust as necessary" ; exit 1 ; }
  done


if [ "$REBRANDING_DISABLED" == "true" ]
  then
    show_warning "Not Rebranding:" "ensure that you don't make this available publicly until rebranded, in order to comply with bluesky-social/social-app guidelines"
    echo "https://github.com/bluesky-social/social-app?tab=readme-ov-file#forking-guidelines"
  else
    # Default REBRANDING_SCRIPT if not set
    if [ "$REBRANDING_SCRIPT" == "" ]; then
      REBRANDING_SCRIPT="$script_dir/rebranding/run-rewrite.sh"
    fi
    
    if [ ! -f "$REBRANDING_SCRIPT" ]; then
      show_error "Rebranding Script Not Found:" "please check REBRANDING_SCRIPT path: $REBRANDING_SCRIPT"
      show_info "To disable rebranding," "set REBRANDING_DISABLED=true in $params_file"
      echo "https://github.com/bluesky-social/social-app?tab=readme-ov-file#forking-guidelines"
      exit 1
    fi
    
    show_heading "Rebranding repos: $REBRANDED_REPOS" "by scripted changes"
    REBRANDING_SCRIPT_ABS="`realpath "$REBRANDING_SCRIPT"`"
    [ "$REBRANDING_NAME" == "" ] && { show_error "Brand name undefined:" "please set REBRANDING_NAME in $params_file" ; exit 1 ; }
    for branded_repo in $REBRANDED_REPOS
      do
        (
          cd "$script_dir/repos/$branded_repo"
          show_info "Branching $branded_repo" "before applying branding changes"
          $script_dir/autobranch.sh -C local-rebranding-$REBRANDING_NAME work dockerbuild
        )
      done
    show_info "Rebranding for $REBRANDING_NAME" "by scripted changes"
    "$REBRANDING_SCRIPT_ABS" "$REBRANDING_DIR" || { show_error "Rebranding script error:" "Please examine and correct before continuing; ran $REBRANDING_SCRIPT_ABS \"$REBRANDING_DIR\"" ; exit 1 ; }
    for branded_repo in $REBRANDED_REPOS
      do
        (
          cd "$script_dir/repos/$branded_repo"
          git diff --exit-code --stat && { show_warning "no changes to $branded_repo:" "check if branding config is correct" ; exit 0 ; }
          show_info "Committing branding changes" "to $branded_repo"
          git commit -a -m "Automatic rebranding to $REBRANDING_NAME" || {
            show_error "Error auto-committing branding changes:" "retrying with git hooks disabled, but you may want to review the above errors"
            git commit --no-verify -a -m "Automatic rebranding to $REBRANDING_NAME (hooks disabled due to error)" || {
              show_error "Error auto-committing branding changes:" "even when git hooks disabled; please correct in $repoDir"
              exit 1
            }
          }
        )
      done
  fi

show_heading "Deleting existing dockerbuild branches" "from the different repositories"
for repoDir in $repoDirs
  do
    (
      cd $repoDir
      echo "$blue_color$clear_bold`basename ${repoDir}`$reset_color"
      $script_dir/autobranch.sh -D dockerbuild local-rebranding-$REBRANDING_NAME
    ) || { show_error "Error deleting dockerbuild branch:" "inspect $repoDir and adjust as necessary" ; exit 1 ; }
  done

show_heading "Patching each repository" "with changes required for docker build"
# 0) apply mimimum patch to build images, regardless self-hosting.
#      as described in https://github.com/bluesky-social/atproto/discussions/2026 for feed-generator/Dockerfile etc.
# NOTE: this op checks out a new branch before applying patch, and stays on the new branch
make patch-dockerbuild checkoutbranchargs=-B commitargs=--no-verify


