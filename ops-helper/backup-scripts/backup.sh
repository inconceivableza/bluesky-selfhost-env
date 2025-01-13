#!/bin/sh
set -e

timestamp=$(date +%Y%m%d_%H%M%S)
staging_dir="/staging/${timestamp}"
mkdir -p "$staging_dir"

# Copy regular files
for data_path in $BACKUP_PATHS
  do
    if [ -d "$data_path" ]; then
      echo "Backing up files from $data_path"
      cp -r $data_path "$staging_dir/" || true
    else
      echo could not find $data_path to backup
    fi
  done

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
        PGPASSFILE=~/.pgpass pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" \
            $POSTGRES_EXTRA_OPTS -Fc -f "$postgres_dir/${db}.pgdump" "$db"
    done

    # Remove .pgpass file
    rm ~/.pgpass
fi

# Handle SQLite databases
if [ -n "$SQLITE_PATHS" ]; then
    echo "Backing up SQLite databases"
    for SQLITE_PATHSPEC in $SQLITE_PATHS; do
        echo searching for databases matching $SQLITE_PATHSPEC
        for db in $(find /data/ -path $SQLITE_PATHSPEC); do
            db_rel_path=${db#/data/}
            db_dir="$staging_dir/$(dirname "$db_rel_path")"
            mkdir -p "$db_dir"

            echo "Backing up database: $db"
            sqlite3 "$db" ".backup '$staging_dir/$db_rel_path'"
        done
    done
fi

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

