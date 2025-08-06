#!/bin/sh
set -e

# assumes $RESTIC_REPOSITORY is set, with the repository location

timestamp=$(date +%Y%m%d_%H%M%S)
staging_dir="/staging/${timestamp}"
mkdir -p "$staging_dir"

# these are manually created areas for storing database exports, not mounted volume locations
mkdir -p /data/sqlite /data/postgres

# Handle PostgreSQL databases
if [ -n "$POSTGRES_HOST" ]; then
    echo "Backing up PostgreSQL databases"
    postgres_dir="$staging_dir/postgres"
    mkdir -p "$postgres_dir"

    # Create .pgpass file for passwordless connection
    echo > ~/.pgpass
    chmod 600 ~/.pgpass
    echo "$POSTGRES_HOST:$POSTGRES_PORT:*:$POSTGRES_USER:$POSTGRES_PASSWORD" > ~/.pgpass

    # Get list of databases, excluding templates and postgres
    databases=$(PGPASSFILE=~/.pgpass psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" postgres \
        -t -c "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres')")

    for db in $databases; do
        echo "Backing up PostgreSQL database: $db"
        PGPASSFILE=~/.pgpass restic backup --stdin-filename /data/postgres/${db}.pgdump --stdin-from-command -- \
            pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" $POSTGRES_EXTRA_OPTS -Fc "$db"
    done

    # Remove .pgpass file
    rm ~/.pgpass
fi

# Handle SQLite databases
if [ -n "$SQLITE_PATHS" ]; then
    echo "Backing up SQLite databases"
    for SQLITE_SPEC in $SQLITE_PATHS; do
        SQLITE_NAME=${SQLITE_SPEC/:*}
        SQLITE_PATHSPEC=${SQLITE_SPEC#*:}
        sqlite_staging_dir=${staging_dir}/$SQLITE_NAME
        echo SQLITE_SPEC $SQLITE_SPEC
        echo SQLITE_NAME $SQLITE_NAME
        echo SQLITE_PATHSPEC "$SQLITE_PATHSPEC"
        echo searching for databases matching "$SQLITE_PATHSPEC" with target $sqlite_staging_dir
        for db in $(find /data/ -path "$SQLITE_PATHSPEC"); do
            db_name="$(basename "$db")"
            db_dir="$(dirname "$db")"
            staging_db_dir="$sqlite_staging_dir/$db_dir"
            echo making directory $staging_db_dir for $db
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
        done
        echo "Backing up databases in $SQLITE_PATHSPEC to restic repository under $SQLITE_NAME"
        restic backup --stdin-filename /data/${SQLITE_NAME}.tar --stdin-from-command -- \
            tar -cf - -C "${sqlite_staging_dir}" data/
    done
fi

# Copy regular files
for data_path in $BACKUP_PATHS
  do
    if [ -d "$data_path" ]; then
      echo "Backing up files from $data_path"
      restic backup $data_path 
    else
      echo could not find $data_path to backup
    fi
  done

exit 1

# Create archive
echo "Creating archive of whole backup"
backup_filename=${RCLONE_FILENAME_PREFIX}backup_${timestamp}.tar.gz
tar czf "/staging/$backup_filename" -C "$staging_dir" .

# Upload to Hetzner Object Storage
echo "Uploading to Hetzner"
rclone copy "/staging/$backup_filename" "hetzner:$RCLONE_PATH"

# Upload to AWS S3 Glacier
# rclone copy "/staging/$backup_filename" "glacier:$RCLONE_PATH"

# Cleanup
echo "Cleaning up..."
rm -rf "$staging_dir" "/staging/backup_${timestamp}.tar.gz"

echo "Done"


