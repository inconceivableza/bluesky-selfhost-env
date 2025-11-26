#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="$(cd `dirname "$script_path"`/.. ; pwd)"
. "$script_dir/utils.sh"
source_env

make $script_dir/config/bgs-secrets.env

function request_crawl() {
  show_info "Requesting crawl" "of PDS $pdsFQDN"
  . $script_dir/config/bgs-secrets.env
  wget -qO- --method=POST --body-data="{\"hostname\": \"$pdsFQDN\"}" --header="Content-Type: application/json" --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/pds/requestCrawl"
}

function request_sync() {
  show_info "Requesting sync" "of PDS $pdsFQDN"
  . $script_dir/config/bgs-secrets.env
  wget -qO- --method=POST --header="Content-Type: application/json" --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/pds/resync?host=$pdsFQDN"
}

function get_status() {
  . $script_dir/config/bgs-secrets.env
  wget "$@" -O- --method=GET --header="Content-Type: application/json" --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/pds/resync?host=$pdsFQDN" 
}

function status_sync() {
  status="$(get_status -q)"
  return_code="$?"
  [ "$return_code" != 0 ] && {
    status_output="$(get_status -q --content-on-error --save-headers)"
    status_headers="$(echo "$status_output" | sed '/^\r*$/q')"
    status_line=$(echo "$status_headers" | grep -m 1 '^HTTP')
    status_code=$(echo "$status_line" | awk '{print $2}')
    status_message=$(echo "$status_line" | awk '{$1=""; $2=""; print $0}' | sed 's#^[[:space:]]*##;s#[[:space:]]*$##')
    status_body="$(echo "$status_output" | sed '1,/^\r*$/d')"
    status_error="$(echo "$status_body" | jq -r .error)"
    status="$(echo "$status_body" | jq --arg status_code "$status_code" --arg status_message "$status_message" '.status_code = ($status_code | tonumber) | .status_message = ($status_message)')"
    [[ "$status_code" == 404 && "$status_error" == "no resync found for given PDS" ]] && return_code=16
  }
  show_info --oneline "PDS Sync Status:"
  echo "$status" | jq
  return $return_code
}

request_crawl
request_sync

interrupted=

function interrupt() {
  show_info --oneline "Stopping monitoring" "after Ctrl-C"
  interrupted=true
}

trap interrupt SIGINT

show_heading "Monitoring pds sync" "press Ctrl-C to stop; will show bgs and pds logs as well as periodic status updates"

$script_dir/do-logs.sh -f --since=1m bgs pds &
log_pid=$!

while [ "$interrupted" != "true" ] ; do
  status_sync
  return_code="$?"
  [ "$return_code" == 16 ] && { show_info --oneline "Sync complete" "so stopping monitoring" ; break ; }
  sleep 2
done

show_info --oneline "Stopping logging"
kill -SIGINT $log_pid
sleep 1
kill $log_pid
wait "$log_pid"

