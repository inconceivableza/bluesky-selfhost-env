#!/bin/sh
set -e

# restores a bluesky backup from a backup file to a target path

if [ -z "$1" ]; then
    echo "Usage: $0 <backup_file> [target_path]"
    exit 1
fi

backup_file="$1"
target_path="${2:-/staging}"
staging_dir="${target_path}/$(basename "$backup_file" .tar.gz | sed 's/backup/restore/')"

# Create temporary directory
mkdir -p "$staging_dir"

# Extract backup
tar xzf "$backup_file" -C "$staging_dir"

# Restore PostgreSQL databases
if [ -d "$staging_dir/postgres" ]; then
    echo "Restoring PostgreSQL databases"

    # Create .pgpass file
    echo > ~/.pgpass
    chmod 600 ~/.pgpass
    echo "$POSTGRES_HOST:$POSTGRES_PORT:*:$POSTGRES_USER:$POSTGRES_PASSWORD" > ~/.pgpass

    for dump_file in "$staging_dir/postgres"/*.pgdump; do
        db_name=$(basename "$dump_file" .pgdump)
        echo "Restoring PostgreSQL database: $db_name"

        # Create database if it doesn't exist
        echo creating database
        PGPASSFILE=~/.pgpass psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" postgres \
            -c "CREATE DATABASE $db_name;" || true

        # Restore database
        echo restoring database
        PGPASSFILE=~/.pgpass pg_restore -v -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" \
            -d "$db_name" --clean --if-exists "$dump_file"
    done

    # Remove .pgpass file
    rm ~/.pgpass
fi

# Restore SQLite databases
find "$staging_dir" -name "*.sqlite" -type f | while read db_file; do
    rel_path=${db_file#$staging_dir/}
    target_db="/data/$rel_path"
    target_dir=$(dirname "$target_db")

    echo "Restoring SQLite database: $rel_path"
    mkdir -p "$target_dir"
    cp "$db_file" "$target_db"
done

# Restore regular files to volumes
for data_path in $BACKUP_PATHS
  do
    src_path="`dirname "$data_path"`"
    if [ -d "$src_path" ]; then
      echo "Restoring files from $src_path"
      cp -r "$src_path" "$data_path/"
    else
      echo could not find $src_path to restore
    fi
    # FIXME: why is it copying /data to /data/pds/data/
  done

echo "Restore completed"

