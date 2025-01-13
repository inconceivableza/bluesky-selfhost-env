#!/bin/sh

restic cat config 2>/dev/null || {
  echo Initializing restic repository at ${RESTIC_REPOSITORY}
  restic init --from-password-file ${RESTIC_PASSWORD_FILE}
}

