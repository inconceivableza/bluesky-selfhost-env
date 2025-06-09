#!/bin/sh
restic_profiles="$(resticprofile profiles | grep '^  .*:' | grep -v '\[.*\]' | sed 's/^  //' | cut -d: -f1)"
local_profiles="$(echo "$restic_profiles" | grep -v "remote-")"
remote_profiles="$(echo "$restic_profiles" | grep "remote-")"

echo Will backup the following local profiles: $local_profiles
echo and the following remote profiles: $remote_profiles

# these are manually created areas for storing database exports, not mounted volume locations
mkdir -p /data/sqlite /data/postgres

errors=""
local_success=""
remote_success=""

for p in $local_profiles
  do
    if RESTIC_NO_AUTO_REMOTE=1 resticprofile $p.backup
      then
        local_success="$local_success $p"
      else
        errors="$errors $p"
      fi
  done

for p in $remote_profiles
  do
    if resticprofile $p.copy
      then
        remote_success="$remote_success $p"
      else
        errors="$errors $p"
      fi
  done

echo Successfully backed up the following local profiles: $local_success
echo Successfully backed up the following remote profiles: $remote_success
if [[ "$errors" == "" ]]
  then
    echo No profile failures detected
  else
    echo Errors backing up the following restic profiles: $errors 2>&1
  fi

