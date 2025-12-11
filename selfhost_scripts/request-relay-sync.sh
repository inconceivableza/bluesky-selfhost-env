#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="$(cd `dirname "$script_path"`/.. ; pwd)"
. "$script_dir/utils.sh"
source_env

make $script_dir/config/relay-secrets.env

function get_relay_auth() {
  . $script_dir/config/relay-secrets.env
  python3 -c "import base64, os ; pw = os.getenv('RELAY_ADMIN_KEY') ; print(base64.b64encode(f'admin:${RELAY_ADMIN_KEY}'.encode('UTF-8')).decode('UTF-8'))"
}

function request_crawl() {
  show_info "Requesting crawl" "of PDS $pdsFQDN"
  RELAY_ADMIN_AUTH="$(get_relay_auth)"
  wget -qO- --method=POST --body-data="{\"hostname\": \"$pdsFQDN\"}" --header="Content-Type: application/json" --header="Authorization: Basic ${RELAY_ADMIN_AUTH}" "https://$relayFQDN/admin/pds/requestCrawl"
}

function get_status() {
  RELAY_ADMIN_AUTH="$(get_relay_auth)"
  wget "$@" -O- --method=GET --header="Content-Type: application/json" --header="Authorization: Basic ${RELAY_ADMIN_AUTH}" "https://$relayFQDN/xrpc/com.atproto.sync.getHostStatus?hostname=$pdsFQDN" 
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

function jq_pds_repos() {
  echo "$pds_repo_json" | jq -r "$@" || { show_error "error in jq request" "$@" ; }
}

function request_account_pulls() {
  # this doesn't actually do anything useful; it returns 404s if the relay doesn't know the account
  show_info "Requesting accounts" "from PDS $pdsFQDN"
  pds_repo_json="$(wget -qO- https://$pdsFQDN/xrpc/com.atproto.sync.listRepos)"
  for did in $(jq_pds_repos '.repos[].did'); do
    echo -n "querying status for $did..."
    repo_status="$(wget -qO- https://$relayFQDN/xrpc/com.atproto.sync.getRepoStatus?did=$did)"
    echo $repo_status
  done
}

request_crawl
request_account_pulls


exit 1

interrupted=

function interrupt() {
  show_info --oneline "Stopping monitoring" "after Ctrl-C"
  interrupted=true
}

trap interrupt SIGINT

show_heading "Monitoring pds sync" "press Ctrl-C to stop; will show relay and pds logs as well as periodic status updates"

$script_dir/do-logs.sh -f --since=1m relay pds &
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

