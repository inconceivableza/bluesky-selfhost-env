#!/usr/bin/env bash

# This patches the branded repositories based on the configured branding rules
# If you only want to apply it to particular repositories, pass them on the commandline

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"
. "$script_dir/apply-feature-branches.sh"
source_env

repoDirs="`make echo | grep ^repoDirs: | sed 's/^repoDirs: //'`"
missingRepos="`for repoDir in ${repoDirs}; do [ -d "$repoDir" ] || echo $repoDir ; done`"

function show_usage() {
  echo "Syntax $0 [-?|-h|--help] [--no-fetch] [-n|--dry-run] [repos...]"
}

do_fetch=1
dry_run=
n=0
while [ "$#" -gt "$n" ]
  do
    [[ "$1" == "--no-fetch" ]] && { do_fetch=0 ; shift 1 ; continue ; }
    [[ "$1" == "-n" || "$1" == "--dry-run" ]] && { dry_run=1 ; shift 1 ; continue ; }
    [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" ]] && { show_usage >&2 ; exit ; }
    [[ "${1#-}" != "$1" ]] && { show_warning "Unknown parameter" "$1" ; show_usage >&2 ; exit 1 ; }
    # a non-option param
    n=$((n+1))
  done

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
  git status --porcelain --untracked-files=no --ignore-submodules=all
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

show_heading "Cloning source code" "from the different repositories"
make cloneAll

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
          # the likely scenario is that this branch is under construction for the first time; set it up accordingly if we can get the right config
          if git_branch_present $required_branch_name
            then
              show_info --oneline "$repo_key: branch $required_branch_name" "is present locally but not at $required_branch; presume it is being made but not pushed yet"
              base_branch=$required_branch_name
            else
              local intended_base_ref="$(yq -r ".${repo_key} // {} | .[\"${required_branch_name}\"].base" "$script_dir/$FEATURE_BRANCH_RULES")"
              if [[ "$intended_base_ref" != "" && "$intended_base_ref" != "null" ]]; then
                show_warning --oneline "Could not find $required_branch" "which is the expected base for $repo_key; presume it is being constructed for first time from $intended_base_ref"
                if git_ref_present $intended_base_ref; then
                  if [ "$dry_run" == 1 ]; then
                    show_info --oneline "Would create new branch $required_branch_name" "based on $intended_base_ref"
                  else
                    show_info --oneline "Creating new branch $required_branch_name" "based on $intended_base_ref"
                    git checkout -b $required_branch_name $intended_base_ref
                  fi
                  base_branch=$required_branch_name
                else
                  show_error --oneline "Could not find $required_branch" "which is the expected base for $repo_key, and could not find intended base ref $intended_base_ref; cannot continue"
                  return 1
                fi
              else
                show_error --oneline "Could not find $required_branch" "which is the expected base for $repo_key, and could not find intended base ref in branch rules; cannot continue"
                return 1
              fi
            fi
        fi
      if git_is_ancestor $required_branch
        then
          show_info --oneline "$repo_key: branch $current_branch" "includes $required_branch changes"
          base_branch=$required_branch
        else
          show_warning --oneline "$repo_key: branch $current_branch" "does not include $required_branch changes"
          if git_branch_present $required_branch_name
            then # we know $required_branch exists because we checked $required_missing above
              if [ "$dry_run" == 1 ]; then
                show_info --oneline "Would switch to $required_branch_name" "as it is present in repo"
              else
                show_info --oneline "Switching to $required_branch_name" "as it is present in repo"
                git checkout $required_branch_name
              fi
              base_branch=$required_branch
          else
            if [ "$dry_run" == 1 ]; then
              show_info --oneline "Would check out $required_branch_name" "from $required_branch"
            else
              show_info --oneline "Checking out $required_branch_name" "from $required_branch"
              git checkout -b $required_branch_name $required_branch
            fi
            base_branch=$required_branch
          fi
        fi
      base_branch_names["$repo_key"]="$base_branch"
      return 0
    else
      local potential_branches="$(yq -r ".${repo_key} // {} | keys | .[]" "$script_dir/$FEATURE_BRANCH_RULES")" present_base_branch
      [ "$potential_branches" == "" ] && {
        show_info --oneline "Will not branch $repo_key" "as branch-rules are not configured for it"
        return 0
      }
      show_info --oneline "Searching other potential base branches" $potential_branches
      for potential_base_branch in $potential_branches
        do
          if git_branch_present $potential_base_branch
            then
              # $potential_base_branch exists in local git repo
              show_info --oneline "Found $potential_base_branch" "in current repo; will check if using"
              present_base_branch=$potential_base_branch
          elif git_branch_present ${fork_repo_name:-fork}/$potential_base_branch
            then
              potential_base_branch=${fork_repo_name:-fork}/$potential_base_branch
              show_info --oneline "Found $potential_base_branch" "in fork; will check if using"
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
          base_branch_names["$repo_key"]="${potential_base_branch##*/}"
          if [ "$dry_run" == 1 ]; then
            show_warning --oneline "$repo_key branch $current_branch" "doesn't match any potential base branch; would switch branch to latest $potential_base_branch"
          else
            show_warning --oneline "$repo_key branch $current_branch" "doesn't match any potential base branch; will switch branch to latest $potential_base_branch"
            git checkout $potential_base_branch
          fi
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
    if [ "$dry_run" == 1 ]; then
      show_info "Would have run" "${ops}"
    else
      ${ops}
    fi
  done
  [ "$dry_run" == 1 ] && return 0
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
  [ "$REBRANDING_DIR" == "" ] && REBRANDING_DIR=repos/social-app/conf
  REBRANDING_DIR_ABS="$(cd $script_dir ; cd $REBRANDING_DIR ; pwd)"
  rebranding_args="--commit-parts"
  [ "$dry_run" == 1 ] && rebranding_args="--check-only --keep-going"
  "$REBRANDING_SCRIPT_ABS" $rebranding_args "$REBRANDING_DIR_ABS" || {
    show_error "Rebranding script error:" "Please examine and correct before continuing; ran $REBRANDING_SCRIPT_ABS \"$REBRANDING_DIR_ABS\""
    return 1
  }
  return 0
}

function autocreate_branch {
  update=0
  [[ "$1" == "-u" || "$1" == "--update" ]] && { update=1; shift 1 ; }
  merge_branch="$1"
  merge_branch_local=${merge_branch##*/}
  merge_branch_base="$2"
  should_run=$update
  show_info --oneline "checking for $merge_branch" "and $merge_branch_local"
  git_branch_present $merge_branch; remote_branch_missing=$?
  git_branch_present $merge_branch_local; local_branch_missing=$?
  if [ "$should_run" == 0 ]; then
    if [ "$remote_branch_missing" == 1 ]; then
      should_run=1
    fi
  fi
  if [ "$should_run" == 0 ]; then
    show_info --oneline "Branch $merge_branch" "exists, and not updating; no need to create"
    return 0
  else
    [ "$remote_branch_missing" == 1 ] && show_warning --oneline "Branch $merge_branch" "is missing"
    if [[ "$local_branch_missing" == 0 && "$update" == "0" ]]; then
      show_info --oneline "Found local branch $merge_branch_local" "which hasn't yet been pushed to remote; will use that"
      return 2
    else
      current_branch=$(git_current_branch)
      if [ "$local_branch_missing" == 1 ]; then
        if [ "$dry_run" == 1 ]; then
          show_info "Would create branch" "$merge_branch_local on $repo_key, based on $merge_branch_base"
        else
          show_info "Will create branch" "$merge_branch_local on $repo_key, based on $merge_branch_base; pushing to remote should be done manually once checked"
          git checkout -b "$merge_branch_local" "$merge_branch_base" || { show_error "Could not checkout branch" ; return 1; }
        fi
      else
        if [ "$dry_run" == 1 ]; then
          show_info "Branch exists but is out of date" "$merge_branch_local on $repo_key; would repoint to where we are"
        else
          show_info "Branch exists but is out of date" "$merge_branch_local on $repo_key; will repoint to where we are"
          git checkout "$merge_branch_local" || { show_error "Could not checkout branch" ; return 1; }
          git merge "$merge_branch_base" || { show_error "Could not merge base branch" ; return 1; }
        fi
      fi
      application_result=0
      if [ $branch_type -eq 1 ]; then
        apply_selfhost_patching_changes || application_result=1
      elif [ $branch_type -eq 2 ]; then
        if [ "$REBRANDING_DISABLED" == "true" ]; then
          show_warning "Not Rebranding:" "ensure that you don't make this available publicly until rebranded, in order to comply with bluesky-social/social-app guidelines"
          echo "https://github.com/bluesky-social/social-app?tab=readme-ov-file#forking-guidelines"
          application_result=1
        else
          apply_rebranding || application_result=1
        fi
      fi
      [ "$application_result" == 1 ] && { show_warning "Error applying self-host patching changes" "please inspect $repo_key and correct before continuing" ; return 1 ; }
      if [ "$dry_run" == 1 ]; then
        show_info --oneline "Would restore original checked-out branch $current_branch" "for $repo_key"
      else
        show_info --oneline "Restoring original checked-out branch $current_branch" "for $repo_key"
        git checkout $current_branch || { 
          show_warning "Error switching back to current branch" "possibly because of untracked files; retrying with --force"
          git checkout --force $current_branch || {
            show_error "Could not checkout current branch" "please revert to correct branch manually"
            return 1
          }
        }
      fi
      return 2 # this indicates to use merge_branch_local rather than the remote
    fi
  fi
  return 0
}

# 2. Merge any branches in branch-rules for this branch that haven't been merged, auto-creating as required

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
      merge_branches="$(yq -r ".[\"${repo_key}\"] // {} | .[\"${base_branch_name}\"] // {} | .merge // [] | .[]" "$script_dir/$FEATURE_BRANCH_RULES")"
      [ "$merge_branches" == "" ] && {
        show_info --oneline "will not check branches for $repo_key" "as branch-rules don't list any"
        exit 0
      }
      (
        prepare_apply_feature_branches -u $base_branch_name $current_branch
        show_info "merging branches into $actual_target:" "please handle any issues that crop up by adjusting the branches if they don't merge, but version-suffixing to prevent issues with earlier versions"
        for merge_branch in $merge_branches
          do
            determine_autocreate_branch "$merge_branch" ; branch_type=$?
            merge_branch_local=${merge_branch##*/}
            selected_merge_branch=$merge_branch
            autocreate_result=0
            [ $branch_type -ne 0 ] && {
              # this would base it off the base
              # merge_branch_base=$(yq -r ".[\"${repo_key}\"] // {} | .[\"${base_branch_name}\"] // {} | .base" $script_dir/$FEATURE_BRANCH_RULES)
              merge_branch_base="$current_branch"
              show_info "autocreating $merge_branch" "in $repoName"
              flags=""
              [ $branch_type -eq 2 ] && flags="-u" # only update the branding automatically
              autocreate_branch $flags "$merge_branch" "$merge_branch_base" ; autocreate_result=$?
              [ $autocreate_result -eq 1 ] && { show_error "error autocreating $merge_branch" "please correct in $repo_key and and resume" ; exit 1 ; }
              [ $autocreate_result -eq 2 ] && selected_merge_branch="$merge_branch_local"
            }
            if [ "$dry_run" == 1 ]; then
              show_info "merging $selected_merge_branch into $actual_target:" "in $repoName"
            else
              show_info "merging $selected_merge_branch into $actual_target:" "in $repoName"
              git merge $selected_merge_branch || { show_error "error merging $selected_merge_branch:" please correct and then re-run to apply all merge branches $merge_branches ; exit 1 ; }
              [ $autocreate_result -eq 2 ] && {
                local_commit="$(git log -1 --format=%H $merge_branch_local 2>/dev/null)"
                remote_commit="$(git log -1 --format=%H $merge_branch 2>/dev/null)"
                [[ "$local_commit" == "$remote_commit" ]] || show_info "Local changes made" "consider pushing $merge_branch_local to $merge_branch"
              }
            fi
          done
      ) || { show_error "Error applying feature branches:" "inspect $repo_key and adjust as necessary" ; error_repos="$error_repos $repo_key"; }
      cd "$script_dir"
    fi
  done

[ "$error_repos" != "" ] && {
  show_error "Could not apply merging of branches successfully" for $error_repos
  show_warning --oneline "Please see errors above" "and correct"
  exit 1
}
