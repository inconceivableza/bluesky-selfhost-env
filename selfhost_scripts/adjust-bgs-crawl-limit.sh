#!/bin/bash

script_path="`realpath "$0"`"
script_dir="$(cd `dirname "$script_path"`/.. ; pwd)"
. "$script_dir/utils.sh"
source_env

. "$script_dir/config/secrets-passwords.env"

[ "$bgsFQDN" == "" ] && { show_warning "Couldn't find bgs domain" "from bgsFQDN environment; please check $params_file" >&2 ; exit 1 ; }
[ "$BGS_ADMIN_KEY" == "" ] && { show_warning "Couldn't find bgs admin key" "from environment or secrets file; please check BGS_ADMIN_KEY in $params_file and $script_dir/config/secrets-passwords.env" >&2 ; exit 1 ; }

# can pass this on the commandline or set it in the .env
[ "$#" -gt 0 ] && {
   BGS_LIMIT="$1"
}
[ "$BGS_LIMIT" == "" ] && BGS_LIMIT=500

previous_limit="$(curl -s -L https://$bgsFQDN/admin/subs/perDayLimit -H "Authorization: Bearer ${BGS_ADMIN_KEY}" | jq -r .limit)"
if [ "$previous_limit" == "$BGS_LIMIT" ]
  then
    show_info --oneline "Relay crawl limit" "already set to $BGS_LIMIT; not adjusting"
  else
    curl  -L -X POST https://$bgsFQDN/admin/subs/setPerDayLimit?limit=500 -H "Authorization: Bearer ${BGS_ADMIN_KEY}"
    new_limit="$(curl -s -L https://$bgsFQDN/admin/subs/perDayLimit -H "Authorization: Bearer ${BGS_ADMIN_KEY}" | jq -r .limit)"
    show_info --oneline "Relay crawl limit" "was $previous_limit, adjusted to $new_limit"
  fi

