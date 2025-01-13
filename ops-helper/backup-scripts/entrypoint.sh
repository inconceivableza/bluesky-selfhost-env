#!/bin/sh
set -e

# Install required packages
apk add --no-cache sqlite dcron tzdata postgresql16-client curl libc6-compat
cd /staging
curl -L -O https://github.com/mcuadros/ofelia/releases/download/v0.3.14/ofelia_0.3.14_linux_amd64.tar.gz
tar xzf ofelia_0.3.14_linux_amd64.tar.gz -C /usr/bin ofelia
chmod a+x /usr/bin/ofelia
echo path is $PATH
ls -l /usr/bin/ofelia

/usr/bin/ofelia validate && /usr/bin/ofelia daemon

