#!/bin/sh

restic cat config 2>/dev/null || {
  echo Initializing restic repository at ${RESTIC_REPOSITORY}
  restic init
}

if [[ "$RESTIC_REMOTE_REPO1" != "" ]]
  then
    restic -r $RESTIC_REMOTE_REPO1 init  --from-repo $RESTIC_REPOSITORY --copy-chunker-params
  fi

if [[ "$RESTIC_REMOTE_REPO2" != "" ]]
  then
    restic -r $RESTIC_REMOTE_REPO2 init  --from-repo $RESTIC_REPOSITORY --copy-chunker-params
  fi

if [[ "$RESTIC_REMOTE_REPO3" != "" ]]
  then
    restic -r $RESTIC_REMOTE_REPO3 init  --from-repo $RESTIC_REPOSITORY --copy-chunker-params
  fi

