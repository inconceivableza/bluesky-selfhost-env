#!/bin/sh
SQLITE_NAME="$1"
SQLITE_TREE="$2"
timestamp=$(date +%Y%m%d_%H%M%S)
staging_dir="/staging/${timestamp}"
sqlite_staging_dir=${staging_dir}/$SQLITE_NAME
echo searching for databases matching "$SQLITE_TREE//*.sqlite" with target $sqlite_staging_dir >&2
for db in $(find "$SQLITE_TREE" -name "*.sqlite"); do (
    db_name="$(basename "$db")"
    db_dir="$(dirname "$db")"
    staging_db_dir="$sqlite_staging_dir/$db_dir"
    mkdir -p "$staging_db_dir"
    if [ -f "$db_dir/key" ]
      then
        # these encrypted databases are written safely for backup
        echo "Backing up encrypted database: $db"
        cp "$db" "$db_dir/key" "$staging_db_dir"
      else
        echo "Backing up database: $db"
        sqlite3 "$db" ".backup '$staging_db_dir/$db_name'"
      fi
) >&2
done
echo "Backing up sqlite databases in $SQLITE_TREE to tar archive under $SQLITE_NAME" >&2
tar -cf - -C "${sqlite_staging_dir}" data/
rm -rf "$sqlite_staging_dir"

