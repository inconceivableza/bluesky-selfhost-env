#!/bin/sh
set -e

timestamp=$(date +%Y%m%d_%H%M%S)
staging_dir="/staging/${timestamp}"
mkdir -p "$staging_dir"

## Data Mapping
# docker volume(containers using): path data description @category
# local (containers using): ./host-path data description @category
# dbtype:dbname (containers using): data description @category
# categories are:
# @system-source-data - original data that's at a system level (primary backup goal)
# @user-source-data - original user data (primary backup goal)
# @derived-data - could be regenerated from the original source data
# @server-config - in principle, this will be recreated for new servers
# @server-runtime - in principle, this will be recreated for new servers
# @executable-code - this is stored in source control or compiled from it

## Caddy
# caddy-data(caddy): /data contains certificates, lets encrypt data etc - generated for each handle @server-config
# caddy-config(caddy): /caddy contains autosave of caddy config @server-config
# local(caddy): ./config/caddy/ contains caddy config @server-config
# local(caddy,*): ./certs/ contains caddy CA certificates for self-signed ops @server-config

## Postgres Database
# database(database): / contains postgres databases @various (see details below):
# - postgres:bgs(bgs): seems to contain high-level info about pds, users, etc @system-source-data
# - postgres:bsky(bsky): appview database - not sure @derived-data @system-source-data
# - postgres:carstore(bgs?): seems to be index to /carstore/ filestore (backfill?) @derived-data?
# - postgres:healthcheck(database): just used for database itself @empty
# - postgres:ozone(ozone*): not using this yet but likely @system-source-data
# - postgres:palomar(palomar): seems to be used for job management @server-runtime
# - postgres:plc(plc): high-level data about dids and operations @system-source-data
# local(database): ./config/init-postgres contains script to setup initial postgres databases @executable-code
# anonymous-pgadmin(pgadmin): / contains pgadmin config @server-runtime

## Redis
# redis(redis): /data/ no files, redis server says dbsize=0 @empty
# only bsky is configured to connect to redis in docker; pds and oauth can also use it

## Opensearch
# opensearch(opensearch): contains opensearch database @derived-data
# TODO: check if there's a way to export an opensearch database?

## Public Ledger of Credentials
# stores data in the plc database

## Personal Data Server
# pds(pds): /blobs/ contains attachments to posts etc @user-source-data
# pds(pds): /actors/ contains sqlite stores for each account, with a key @user-source-data
#   - FIXME for now we're just backing these up without a proper sqlite backup, since we need to configure the key
# pds(pds): / contains sqlite stores for the PDS server @system-source-data

## Big Sky Server
# bgs(bgs): /carstore/ presume this contains backfill data @user-derived-data

## AppView
# bsky(bsky): / contains caches, currently of images @user-derived-data

## Social App
# no local data

## Palomar - backend search that uses opensearch
# no local data, it's stored in database and opensearch

## Jetstream - alternative lightweight data streamer
# jetstream(jetstream): seems empty @user-derived-data
# not running this at the moment

## Ozone - moderation
# no local data, it's stored in database (but we're not running yet)

## Feed Generator
# feed-generator(feed-generator): / sqlite database @system-source-data

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
tar czf "/staging/backup_${timestamp}.tar.gz" -C "$staging_dir" .

# Upload to Hetzner Object Storage
echo "Uploading to Hetzner"
rclone copy "/staging/backup_${timestamp}.tar.gz" "hetzner:$RCLONE_PATH"

# Upload to AWS S3 Glacier
# rclone copy "/staging/backup_${timestamp}.tar.gz" "glacier:$RCLONE_PATH"

# Cleanup
echo "Cleaning up..."
rm -rf "$staging_dir" "/staging/backup_${timestamp}.tar.gz"

echo "Done"

