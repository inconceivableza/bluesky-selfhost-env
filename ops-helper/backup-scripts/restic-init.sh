#!/bin/sh

creds_dir=/resticprofile/credentials

save_passwd() {
  [[ "$1" != "" && ! -f "$2" ]] && {
    echo writing password to "$2"
    touch "$2"
    chmod 0600 "$2"
    echo "$1" > "$2"
  }
}

mkdir -m 0700 -p $creds_dir
save_passwd "$RESTIC_PASSWORD" "$RESTIC_PASSWORD_FILE"
save_passwd "$RESTIC_REMOTE_PASSWORD1" "$creds_dir/remote-repo1-password"
save_passwd "$RESTIC_REMOTE_PASSWORD2" "$creds_dir/remote-repo2-password"
save_passwd "$RESTIC_REMOTE_PASSWORD3" "$creds_dir/remote-repo3-password"

restic cat config 2>/dev/null || {
  echo Initializing restic repository at ${RESTIC_REPOSITORY}
  restic init
}

if [[ "$RESTIC_REMOTE_REPO1" != "" ]]
  then
    restic -r $RESTIC_REMOTE_REPO1 init  --from-repo $RESTIC_REPOSITORY --copy-chunker-params --from-password-file=$RESTIC_PASSWORD_FILE --password-file=$creds_dir/remote-repo1-password
  fi

if [[ "$RESTIC_REMOTE_REPO2" != "" ]]
  then
    restic -r $RESTIC_REMOTE_REPO2 init  --from-repo $RESTIC_REPOSITORY --copy-chunker-params --from-password-file=$RESTIC_PASSWORD_FILE --password-file=$creds_dir/remote-repo2-password
  fi

if [[ "$RESTIC_REMOTE_REPO3" != "" ]]
  then
    restic -r $RESTIC_REMOTE_REPO3 init  --from-repo $RESTIC_REPOSITORY --copy-chunker-params --from-password-file=$RESTIC_PASSWORD_FILE --password-file=$creds_dir/remote-repo3-password
  fi

