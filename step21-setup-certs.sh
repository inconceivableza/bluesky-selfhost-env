#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"
source_env

chmod go-rwx $script_dir/certs # let's not have others snooping our certs

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
          show_info "Manually install certificates" "on the Android device"
          adb shell am start -a android.intent.action.VIEW -d content://com.android.externalstorage.documents/root/primary%3ADownload
          # adb shell am start -n com.android.certinstaller/.CertInstallerMain -a android.intent.action.VIEW -t application/x-x509-ca-cert -d file:///sdcard/Download/
          show_info --oneline "Test in web browser" "by going to https://$socialappFQDN on the device"
        )
    elif [ "$1" == "--ios" ]
      then
        show_heading "Guiding install to iOS" "for mobile testing"
        certs="root.crt intermediate.crt"
        (
          cd $script_dir/certs
          show_info "Manually install certificates" "on the iOS device"
          for cert in $certs; do
            show_info "Certificate installation" "for $cert"
            show_info --oneline "Use Airdrop" "to copy $cert from $script_dir/certs onto the iOS device"
            echo -n Press any key when completed...
            read
            show_info --oneline "Open Settings" "tap on Profile Downloaded and then select Install"
            echo -n Press any key when completed...
            read
            [ "$cert" == root.crt ] && {
              show_info --oneline "Go to Settings → General → About → Certificate Trust Settings" "And for each certificate turn on Enable Full Trust"
              echo -n Press any key when completed...
              read
            }
          done
          show_info --oneline "Test in web browser" "by going to https://$socialappFQDN on the device"
        )
      else
        show_heading --oneline "For mobile testing" "you will need to install the certificates into the mobile devices"
        show_info --oneline "Run this script" "with --android or --ios to install into local mobile device or emulator via adb"
        echo
      fi
    show_heading "Don't forget to install the certificate" "in $script_dir/certs/root.crt into your local web browser"
  else
    show_heading "Certificates will be auto-generated" "using let's encrypt, with $EMAIL4CERTS as the email address"
    echo "This should take place when starting up the test web containers"
  fi

