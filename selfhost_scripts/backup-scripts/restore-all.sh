#!/bin/sh
restic_profiles="$(resticprofile profiles | grep '^  .*:' | grep -v '\[.*\]' | sed 's/^  //' | cut -d: -f1)"
local_profiles="$(echo "$restic_profiles" | grep -v "remote-")"
remote_profiles="$(echo "$restic_profiles" | grep "remote-")"

echo Will restore the following local profiles: $local_profiles
echo
echo NB this is still experimental and has not been tested
echo In particular, it will NOT actually restore postgres databases
read -p "Press Enter to continue..." ___

errors=""
local_success=""
remote_success=""

for p in $local_profiles
  do
    if RESTIC_NO_AUTO_REMOTE=1 resticprofile $p.restore
      then
        local_success="$local_success $p"
      else
        errors="$errors $p"
      fi
  done

echo Successfully restored the following local profiles: $local_success
if [ "$errors" = "" ]
  then
    echo No profile failures detected
  else
    echo Errors restoring the following restic profiles: $errors 2>&1
  fi

