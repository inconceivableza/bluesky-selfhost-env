#!/usr/bin/env bash

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

do_fetch=1
[[ "$1" == "--no-fetch" ]] && { do_fetch=0 ; shift 1 ; }

if [ $# -gt 0 ]
  then
    cmdlineDirs="$@"
    show_info "Will only run on repos" $cmdlineDirs
    repoDirs="$(for cmdlineDir in ${cmdlineDirs}; do echo $script_dir/repos/$cmdlineDir ; done)"
    TARGET_REPOS="$cmdlineDirs"
  else
    TARGET_REPOS="$REBRANDED_REPOS"
  fi

function git_repo_changes() {
  git status --porcelain --untracked-files=no
}

function git_current_branch() {
  # if the current branch name is ambiguous, this will prefix it with head/, but we don't want that for checking it out
  git rev-parse --abbrev-ref HEAD | sed 's#head/##'
}

function git_branch_present() {
  # accepts either a local branch (without /) or a remote (as 'remote/branch')
  local check_present_branch="$1" check_present_branch_ref
  if [ "${check_present_branch##*/}" == "$check_present_branch" ]
    then
      check_present_branch_ref=refs/heads/$check_present_branch
    else
      check_present_branch_ref=refs/remotes/$check_present_branch
    fi
  git show-ref --verify --quiet $check_present_branch_ref
  return $?
}

function git_ref_present() {
  # accepts any ref that is resolvable
  local check_present_ref="$1"
  git show-ref --quiet $check_present_ref
  return $?
}

function git_is_ancestor() {
  # checks whether the given ref is an ancestor of the current commit
  local check_ancestor_ref="$1"
  git merge-base --is-ancestor $check_ancestor_ref HEAD
}

# 1. Check which branch we're on. If not listed in branch-rules, and non of the branches listed there is an ancestor commit:
#    - create the latest branch in branch-rules / the one specified in the environment

cd "$script_dir"
show_heading "Checking for uncommitted changes" "in the specified repositories" $([ $do_fetch -eq 1 ] && echo "and fetching from remotes")
error_repos=""
for repoDir in $repoDirs
  do
    repo_key=$(basename $repoDir)
    echo "$blue_color$clear_bold$repo_key$reset_color"
    (
      cd $repoDir
      [[ -n $(git_repo_changes) ]] && {
        show_warning "$repo_key has uncommitted changes" "See below for details"
        git_repo_changes
        exit 1
      }
      [ $do_fetch -eq 1 ] && git fetch --all
      exit 0
    ) || { show_error "Repo ${repo_key} has changed" "inspect $repo_key and commit/discard as necessary" ; error_repos="$error_repos $repo_key"; }
  done

[ "$error_repos" != "" ] && {
  show_error "Could not switch branches" as changes are present in $error_repos
  show_warning --oneline "Please see errors above" "and correct"
  exit 1
}

cd "$script_dir"
show_heading "Analysing current branch" "from the different repositories"
error_repos=""
declare -A base_branch_names

function analyse_branch() {
  local repo_key="$1"
  echo "$blue_color$clear_bold$repo_key$reset_color"
  local repo_branch_varname=${repo_key//-/_}_branch
  local required_branch=${!repo_branch_varname:-}
  local required_branch_name=${required_branch##*/}
  local current_branch=$(git_current_branch)
  local base_branch=
  if [ "$required_branch" != "" ]
    then
      show_info --oneline "searching for configured" $required_branch
      if ! git_branch_present $required_branch
        then
          show_error "Could not find $required_branch" "which is the expected base for $repo_key"
          return 1
        fi
      if git_is_ancestor $required_branch
        then
          show_info --oneline "$repo_key: branch $current_branch" "includes $required_branch changes"
          base_branch=$required_branch
        else
          show_warning --oneline "$repo_key: branch $current_branch" "does not include $required_branch changes"
          if git_branch_present $required_branch_name
            then # we know $required_branch exists because we checked $required_missing above
              show_info --oneline "switching to $required_branch_name" "as it is present in repo"
              git checkout $required_branch_name
              base_branch=$required_branch
          else
              show_info --oneline "checking out $required_branch_name" "from $required_branch"
              git checkout -b $required_branch_name $required_branch
              base_branch=$required_branch
          fi
        fi
      base_branch_names["$repo_key"]="$base_branch"
      return 0
    else
      local potential_branches="$(yq -r ".${repo_key} // {} | keys | .[]" "$script_dir/$FEATURE_BRANCH_RULES")" present_base_branch
      [ "$potential_branches" == "" ] && {
        show_info --oneline "will not branch $repo_key" "as branch-rules are not configured for it"
        return 0
      }
      show_info --oneline "searching other potential base branches" $potential_branches
      for potential_base_branch in $potential_branches
        do
          if git_branch_present $potential_base_branch
            then
              # $potential_base_branch exists in local git repo
              show_info --oneline "found $potential_base_branch" "in current repo; will check if using"
              present_base_branch=$potential_base_branch
          elif git_branch_present ${fork_repo_name:-fork}/$potential_base_branch
            then
              potential_base_branch=${fork_repo_name:-fork}/$potential_base_branch
              show_info --oneline "found $potential_base_branch" "in fork; will check if using"
              present_base_branch=$potential_base_branch
          else
            continue # doesn't exist, not worth checking
          fi
          if git_is_ancestor $potential_base_branch
            then
              base_branch=$potential_base_branch
            fi
        done
      if [ "$base_branch" == "" ]
        then
          show_warning --oneline "$repo_key branch $current_branch" "doesn't match any potential base branch; will switch branch to latest $potential_base_branch"
          base_branch_names["$repo_key"]="${potential_base_branch##*/}"
          git checkout $potential_base_branch
          return 0
        else
          show_info --oneline "$repo_key branch $current_branch" "includes $base_branch changes; will use its branch configuration"
          base_branch_names["$repo_key"]="${base_branch##*/}"
          return 0
        fi
    fi
}

for repoDir in $repoDirs
  do
    repo_key=$(basename $repoDir)
    cd "$repoDir"
    analyse_branch "$repo_key" || {
      show_error "Error updating to latest branch:" "inspect $repo_key and adjust as necessary"
      error_repos="$error_repos $repo_key"
    }
    cd "$script_dir"
  done

[ "$error_repos" != "" ] && {
  show_error "Could not select branches successfully" for $error_repos
  show_warning --oneline "Please see errors above" "and correct"
  exit 1
}

# 2. Check if any auto-create branches haven't been made (if in the merge list in branch-rules), and create if required:
#    - brightsun/selfhost-patching-changes
#    - brightsun/branding-${REBRANDING_NAME}
#    Then switch back to the current branch

function determine_autocreate_branch() {
  local target_branch=$1
  local base_target_branch="${target_branch##*/}"
  # checks if this matches the two target names, or starts with them (to allow for version suffixes)
  [ "${base_target_branch}" == "selfhost-patching-changes" ] && return 1
  [ "${base_target_branch##selfhost-patching-changes-}" != "${base_target_branch}" ] && return 1
  [ "${base_target_branch}" == "branding-${REBRANDING_NAME}" ] && return 2
  [ "${base_target_branch##branding-${REBRANDING_NAME}-}" != "${base_target_branch}" ] && return 2
  return 0
}

function apply_selfhost_patching_changes() {
  # set directories that these scripts use
  export wDir=${script_dir}
  export rDir=${repoDir}
  export pDir=${script_dir}/patching
  for ops in `ls ${wDir}/patching/1*.sh | grep ${repo_key}`; do
    ${ops}
  done
  # only add already tracked files
  git add -u .
  git commit -m "update: self-host patches" || {
    show_warning "Error committing changes" "will retry without checks"
    git commit -n -m "update: self-host patches" || {
      show_error "Could not commit changes" "please revert to correct branch manually"
      git reset --hard
      return 1
    }
  }
}


function apply_rebranding() {
  # Default REBRANDING_SCRIPT if not set
  if [ "$REBRANDING_SCRIPT" == "" ]; then
    REBRANDING_SCRIPT="$script_dir/rebranding/run-rewrite.sh"
  fi
  if [ ! -f "$REBRANDING_SCRIPT" ]; then
    show_error "Rebranding Script Not Found:" "please check REBRANDING_SCRIPT path: $REBRANDING_SCRIPT"
    show_info "To disable rebranding," "set REBRANDING_DISABLED=true in $params_file"
    echo "https://github.com/bluesky-social/social-app?tab=readme-ov-file#forking-guidelines"
    return 1
  fi
  REBRANDING_SCRIPT_ABS="`cd $script_dir ; realpath "$REBRANDING_SCRIPT"`"
  [ "$REBRANDING_NAME" == "" ] && { show_error "Brand name undefined:" "please set REBRANDING_NAME in $params_file" ; return 1 ; }
  show_info "Rebranding for $REBRANDING_NAME" "by scripted changes"
  REBRANDING_DIR_ABS="$(cd $script_dir ; cd $REBRANDING_DIR ; pwd)"
  "$REBRANDING_SCRIPT_ABS" "$REBRANDING_DIR_ABS" || {
    show_error "Rebranding script error:" "Please examine and correct before continuing; ran $REBRANDING_SCRIPT_ABS \"$REBRANDING_DIR_ABS\""
    return 1
  }
  git diff --exit-code --stat && { show_warning "no changes to $branded_repo:" "check if branding config is correct" ; return 1 ; }
  show_info "Committing branding changes" "to $branded_repo"
  git commit -a -m "Automatic rebranding to $REBRANDING_NAME" || {
    show_error "Error auto-committing branding changes:" "retrying with git hooks disabled, but you may want to review the above errors"
    git commit --no-verify -a -m "Automatic rebranding to $REBRANDING_NAME (hooks disabled due to error)" || {
      show_error "Error auto-committing branding changes:" "even when git hooks disabled; please correct in $repo_key"
      return 1
    }
  }
  return 0
}

cd "$script_dir"
show_heading "Checking auto-created branches" "in each of the target repositories"
error_repos=""
for repoDir in $repoDirs
  do
    repo_key=$(basename $repoDir)
    cd "$repoDir"
    (
      base_branch=${base_branch_names["${repo_key}"]}
      echo "$blue_color$clear_bold$repo_key$reset_color" base branch $base_branch
      base_branch_name=${base_branch##*/}
      merge_branches="$(yq -r ".[\"${repo_key}\"] // {} | .[\"${base_branch_name}\"] // {} | .merge // [] | .[]" "$script_dir/$FEATURE_BRANCH_RULES")"
      [ "$merge_branches" == "" ] && {
        show_info --oneline "will not check branches for $repo_key" "as branch-rules don't list any"
        exit 0
      }
      application_result=0
      for merge_branch in $merge_branches
        do
          determine_autocreate_branch "$merge_branch" ; branch_type=$?
          [ $branch_type -eq 0 ] && { echo $merge_branch is not auto-create ; continue ; }
          merge_branch_local=${merge_branch##*/}
          show_info --oneline "checking for $merge_branch" "and $merge_branch_local"
          if git_branch_present $merge_branch; then
            show_info --oneline "Branch $merge_branch" "exists; no need to create"
          else
            show_warning --oneline "Branch $merge_branch" "is missing"
            if git_branch_present ${merge_branch_local}; then
              show_info --oneline "Found local branch $merge_branch_local" "which hasn't yet been pushed to remote; will use that"
            else
              merge_branch_base=$(yq -r ".[\"${repo_key}\"] // {} | .[\"${base_branch_name}\"] // {} | .base" $script_dir/$FEATURE_BRANCH_RULES)
              show_info "Will create branch" "$merge_branch_local on $repo_key, based on $merge_branch_base; pushing to remote should be done manually once checked"
              current_branch=$(git_current_branch)
              git checkout -b "$merge_branch_local" "$merge_branch_base" || { show_error "Could not checkout branch" ; exit 1; }
              if [ $branch_type -eq 1 ]; then
                apply_selfhost_patching_changes || application_error=1
              elif [ $branch_type -eq 2 ]; then
                if [ "$REBRANDING_DISABLED" == "true" ]; then
                  show_warning "Not Rebranding:" "ensure that you don't make this available publicly until rebranded, in order to comply with bluesky-social/social-app guidelines"
                  echo "https://github.com/bluesky-social/social-app?tab=readme-ov-file#forking-guidelines"
                  application_result=1
                else
                  apply_rebranding || application_result=1
                fi
              fi
              show_info --oneline "Restoring original checked-out branch $current_branch" "for $repo_key"
              git checkout $current_branch || { 
                show_warning "Error switching back to current branch" "possibly because of untracked files; retrying with --force"
                git checkout --force $current_branch || {
                  show_error "Could not checkout current branch" "please revert to correct branch manually"
                  exit 1
                }
              }
            fi
          fi
        done
      exit $application_result
    ) || { show_error "Error checking auto-created branches:" "inspect $repo_key and adjust as necessary" ; error_repos="$error_repos $repo_key"; }
    cd "$script_dir"
  done

[ "$error_repos" != "" ] && {
  show_error "Could not check auto-created branches successfully" for $error_repos
  show_warning --oneline "Please see errors above" "and correct"
  exit 1
}

# 3. Merge any branches in branch-rules for this branch that haven't been merged

cd "$script_dir"
show_heading "Applying configured feature branches" "in each of the target repositories"
error_repos=""
for repoDir in $repoDirs
  do
    repo_key=$(basename $repoDir)
    base_branch=${base_branch_names["${repo_key}"]}
    if [ "$base_branch" != "" ]; then
      cd "$repoDir"
      echo "$blue_color$clear_bold$repo_key$reset_color" base branch $base_branch
      base_branch_name=${base_branch##*/}
      (
        $script_dir/apply-feature-branches.sh -u $base_branch_name $current_branch
      ) || { show_error "Error applying feature branches:" "inspect $repo_key and adjust as necessary" ; error_repos="$error_repos $repo_key"; }
      cd "$script_dir"
    fi
  done

[ "$error_repos" != "" ] && {
  show_error "Could not apply merging of branches successfully" for $error_repos
  show_warning --oneline "Please see errors above" "and correct"
  exit 1
}
