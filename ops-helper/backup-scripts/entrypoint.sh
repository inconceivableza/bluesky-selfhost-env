#!/bin/sh
set -e

# Install required packages
apk add --no-cache sqlite tzdata postgresql16-client

# ensure local repository is initialized
/scripts/restic-init.sh

