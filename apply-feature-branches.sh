#!/bin/bash

# This allows the automated creation of updated version branches, by auto-merging specified feature branches
# the feature branches are specified in a branch-rules.yml file, which can be specified
# It should be structured as $repo_name: $target_branch: {base: $base_name, merge: [list of branches to merge]}
# For example:
# social-app:
#   1.99.0-opensky:
#     base: 1.99.0
#     merge:
#       - brightsun/disable-chat

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

set -o allexport
. "$params_file"
set +o allexport

function usage {
  echo ""
  echo "Usage: $0 repo target_branch [allowed_starting_branch ...]"
  echo ""
  echo "Creates target_branch, by applying the merge rules in branches to the configured base branch"
  echo 'Rules are read from $FEATURE_BRANCH_RULES in the env file, or from ./branch-rules-file.yml if not defined'
  echo ""
  echo "Will not do this and exit with an error code if:"
  echo " - there are uncommitted changes"
  echo " - not on target_branch or base_branch or one of the existing allowed_starting_branches"
}

if [[ "$#" -lt 2 ]]
  then
    usage
    exit 1
  fi

repoName="$1"
target_branch="$2"
shift
shift
allowed_starting_branches="$@"
repoDir="$script_dir/repos/$repoName"
rulesFile="$script_dir/branch-rules.yml"
[ "$FEATURE_BRANCH_RULES" != "" ] && rulesFile="$FEATURE_BRANCH_RULES"
rulesFile="`readlink -f "$rulesFile"`" # this makes it non-relative
[ -f "$rulesFile" ] || { show_error "Could not find rules file" "$rulesFile" ; exit 1 ; }
show_info "Rules file" "$rulesFile found"

cd "$repoDir" || { show_error "Could not find repo $repoDir:" "please check" ; exit 1 ; }

git fetch --all
git diff --exit-code --stat || { show_error "Uncommitted changes in $repoName:" "inspect $repoDir and adjust as necessary" ; exit 1 ; }
current_branch="`git rev-parse --abbrev-ref HEAD`"

base_branch="$(yq '.["'$repoName'"]["'$target_branch'"].base' "$rulesFile")"
merge_branches="$(yq '.["'$repoName'"]["'$target_branch'"].merge[]' "$rulesFile")"
if [[ "$base_branch" == "" ]]
  then
    echo base branch for $target_branch is not defined for $repoName in $rulesFile >&2
    exit 1
  fi
show_heading "Will create branch $target_branch" "in $repoName based on $base_branch by merging configured branches" $merge_branches

if [[ "$current_branch" == "$target_branch" ]]
  then
    echo already on $target_branch branch - merging upstream changes from $base_branch
elif [[ "$current_branch" == "`basename $base_branch`" ]]
  then
    echo currently on $current_branch branch - switching to $target_branch and merging upstream changes from $base_branch
elif [[ "$allowed_starting_branches" != "" ]]
  then
    is_allowed=
    for allowed_starting_branch in $allowed_starting_branches
      do
        if [[ "$current_branch" == "$allowed_starting_branch" || "$current_branch" == "$(basename $allowed_starting_branch)" ]]
          then
            is_allowed=true
          fi
      done
    if [[ "$is_allowed" != "true" ]]
      then
        show_error "unknown branch $current_branch" "in $repoName is not one of the allowed starting branches [$allowed_starting_branches], aborting autobranch"
        exit 1
      fi
    echo currently on $current_branch branch - switching to $target_branch and merging upstream changes from $base_branch
fi

if [ -n "$(git branch --list $target_branch)" ]
  then
    show_info "branch $target_branch already exists" "will merge $base_branch in case there are changes"
    git checkout $target_branch
    git merge $base_branch
  else
    show_info "creating branch $target_branch" "based on $base_branch"
    git checkout -b $target_branch $base_branch
  fi

show_info "merging branches into $target_branch:" "please handle any issues that crop up by adjusting the branches if they don't merge, but version-suffixing to prevent issues with earlier versions"
for branch in $merge_branches
  do
    show_info "merging $branch into $target_branch:" "in $repoName"
    git merge $branch
  done
    

