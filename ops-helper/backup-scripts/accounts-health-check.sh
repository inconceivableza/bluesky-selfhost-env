#!/bin/sh

target_dir=`pwd`
# these are the tables that relate to accounts, rather than posts, likes, follows, etc
echo will save files to $target_dir

# postgres first
for db_table in plc:dids plc:operations bgs:actor_infos bgs:pds bgs:repo_event_records bgs:users bsky:actor bsky:actor_state bsky:actor_sync bsky:did_cache bsky:profile 
  do
    src_db=${db_table%:*}
    table=${db_table#*:}
    export PGOPTION=
    [ "$src_db" == "bsky" ] && export PGOPTIONS="--search-path=bsky"
    target_file=$target_dir/$src_db-$table.json
    echo saving $src_db table $table to $(echo $target_file | sed "s#$target_dir/##")
    psql -A -t -c "\\copy (SELECT json_agg(row_to_json($table)) :: text FROM $table) to '$target_file';" $src_db | grep -v '^COPY 1$'
  done

# now sqlite
for db_table in pds/account:account pds/account:actor pds/account:email_token pds/did_cache:did_doc pds/sequencer:repo_seq
  do
    src_db_name=${db_table%:*}
    src_db=/data/$src_db_name.sqlite
    table=${db_table#*:}
    target_file=$target_dir/${src_db_name//\//-}-$table.json
    echo saving $src_db_name table $table to $(echo $target_file | sed "s#$target_dir/##")
    sqlite3 --json $src_db ".once $target_file" "select * from $table;"
  done

