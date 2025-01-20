#!/bin/sh
restic_profiles="`resticprofile profiles | grep '^  .*:' | cut -d: -f1`"
echo Will backup the following profiles: $restic_profiles
errors=""
for p in $restic_profiles
  do
    resticprofile run-schedule backup@$p || { errors="$errors $p" ; }
  done
if [[ "$errors" == "" ]]
  then
    echo Successfully backed up the following restic profiles: $restic_profiles
  else
    echo Errors backing up the following restic profiles: $errors 2>&1
  fi

