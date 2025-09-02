#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"
source_env

if [ "$EMAIL4CERTS" == "internal" ]
  then
    show_heading "Setting up CA" "for self-signed certificates"

    make getCAcert
    [ "$NOINSTALLCERTS" != "true" ] && make installCAcert certCollections

    if [ "$1" == "--android" ]
      then
        show_heading "Installing to Android" "for mobile testing"
        certs="root.crt intermediate.crt"
        (
          cd $script_dir/certs
          certs_dir=Download/certs-$DOMAIN
          adb shell mkdir /sdcard/$certs_dir
          adb push $certs /sdcard/$certs_dir
          show_info "Manually install certificates" "on Android device"
          adb shell am start -a android.intent.action.VIEW -d content://com.android.externalstorage.documents/root/primary%3ADownload
          # adb shell am start -n com.android.certinstaller/.CertInstallerMain -a android.intent.action.VIEW -t application/x-x509-ca-cert -d file:///sdcard/Download/
        )
      else
        show_heading --oneline "For mobile testing" "you will need to install the certificates into the mobile devices"
        show_info --oneline "Run this script" "with --android to install into local android device or emulator via adb"
        echo
      fi
    show_heading "Don't forget to install the certificate" "in $script_dir/certs/root.crt into your local web browser"
  else
    show_heading "Certificates will be auto-generated" "using let's encrypt, with $EMAIL4CERTS as the email address"
    echo "This should take place when starting up the test web containers"
  fi

