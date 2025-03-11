#!/bin/sh
set -e

# Install required packages
apk add --no-cache sqlite tzdata postgresql16-client python3 py3-psycopg-c

# ensure local repository is initialized
/scripts/restic-init.sh

