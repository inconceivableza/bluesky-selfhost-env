#!/bin/sh
restic_profiles="$(resticprofile profiles | grep '^  .*:' | grep -v '\[.*\]' | sed 's/^  //' | cut -d: -f1)"
local_profiles="$(echo "$restic_profiles" | grep -v "remote-")"

# outputs the latest id
for p in $local_profiles
  do
    p_path="$(resticprofile $p.show | grep '^ *path:' | sed 's/^ *path: *//')"
    [ "$p_path" == "" ] && p_path="$(resticprofile $p.show | grep '^ *stdin-filename:' | sed 's/^ *stdin-filename: *//')"
    echo searching for profile $p and path $p_path >&2
    json="$(resticprofile $p.snapshots --host backup.dallan.inclan --path="$p_path" --latest 1 --json -q | grep '^\[')"
    echo "$json" | jq -r ".[0] | .profile=\"$p\""
  done | jq -s '.'

