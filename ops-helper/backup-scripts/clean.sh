#!/bin/bash
set -e

echo This will delete ALL data on this bluesky system. ARE YOU SURE??? Checking in 5 seconds. >&2
sleep 5
read -p "Enter DELETE to confirm" -n 1 -r
echo
if [[ "$REPLY" == "DELETE" ]]
  then
    echo Deleting data...
    for data_path in $BACKUP_PATHS
      do
        echo removing data from $data_path
        rm -r $data_path/*
      done
    for data_path in $SQLITE_PATHS
      do
        echo removing sqlite databases from $data_path
        find $data_path -name "*.sqlite*" -print0 | -xargs -0 rm -r
      done
    echo this script does not yet remove postgres data but the restore cleans it
  else
    echo Confirmation not received. Aborting >&2
  fi

