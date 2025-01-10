#!/bin/sh
set -e

# Install required packages
apk add --no-cache sqlite dcron tzdata postgresql16-client

/scripts/backup.sh

