#!/bin/sh
set -e

echo This will delete ALL data on this bluesky system. ARE YOU SURE??? Checking in 5 seconds. >&2
sleep 5
read -p "Enter DELETE to confirm: " -r
echo
BACKUP_PATHS="/data/bgs/ /data/bsky/ /data/pds/ /data/opensearch/"
POSTGRES_DBS="bgs bsky carstore ozone palomar plc"
errors=
if [[ "$REPLY" == "DELETE" ]]
  then
    echo Deleting data...
    for data_path in $BACKUP_PATHS
      do
        echo removing data from $data_path
        rm -r $data_path/* || errors="$errors $data_path"
      done

    for db in $POSTGRES_DBS
      do
        echo Dropping database $db
        psql postgres -c "drop database ${db};" || errors="$errors database:$db"
      done

    if [[ "$errors" != "" ]]
      then
        echo Errors occurred processing $errors >&2
      fi
  else
    echo Confirmation not received. Aborting >&2
  fi

