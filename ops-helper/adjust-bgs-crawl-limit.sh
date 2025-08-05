#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`/.."
. "$script_dir/utils.sh"
source_env

. "$script_dir/config/secrets-passwords.env"

[ "$bgsFQDN" == "" ] && { echo "Couldn't find bgs domain from bgsFQDN environment; please check $params_file" >&2 ; exit 1 ; }
[ "$BGS_ADMIN_KEY" == "" ] && { echo "Couldn't find bgs admin key from environment or secrets file; please check BGS_ADMIN_KEY in $params_file and $script_dir/config/secrets-passwords.env" >&2 ; exit 1 ; }

curl  -L https://$bgsFQDN/admin/subs/perDayLimit -H "Authorization: Bearer ${BGS_ADMIN_KEY}"
curl  -L -X POST https://$bgsFQDN/admin/subs/setPerDayLimit?limit=500 -H "Authorization: Bearer ${BGS_ADMIN_KEY}"
