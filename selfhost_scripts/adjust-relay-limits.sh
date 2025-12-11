#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="$(cd `dirname "$script_path"`/.. ; pwd)"
. "$script_dir/utils.sh"
source_env

RELAY_SECRETS_FILE="$script_dir/config/relay-secrets.env"
make $RELAY_SECRETS_FILE
. $RELAY_SECRETS_FILE

[ "$relayFQDN" == "" ] && { show_warning "Couldn't find relay domain" "from relayFQDN environment; please check $params_file" >&2 ; exit 1 ; }
[ "$RELAY_ADMIN_KEY" == "" ] && { show_warning "Couldn't find relay admin key" "from environment or secrets file; please check RELAY_ADMIN_KEY in $params_file and $script_dir/config/secrets-passwords.env" >&2 ; exit 1 ; }

function get_relay_auth() {
  echo -n "admin:${RELAY_ADMIN_KEY}" | base64
}

RELAY_ADMIN_AUTH=$(get_relay_auth)

# can pass this on the commandline or set it in the .env
[ "$#" -gt 0 ] && {
   RELAY_SUBS_PER_DAY="$1"
   shift 1
}
[ "$RELAY_SUBS_PER_DAY" == "" ] && RELAY_SUBS_PER_DAY=500

[ "$#" -gt 0 ] && {
   RELAY_PDS_REPO_LIMIT="$1"
   shift 1
}
[ "$RELAY_PDS_REPO_LIMIT" == "" ] && RELAY_PDS_REPO_LIMIT=1000000
[ "$RELAY_PDS_CRAWL_RATE_LIMIT" == "" ] && RELAY_PDS_CRAWL_RATE_LIMIT=10
[ "$RELAY_PDS_PER_SECOND_LIMIT" == "" ] && RELAY_PDS_PER_SECOND_LIMIT=100
[ "$RELAY_PDS_PER_HOUR_LIMIT" == "" ] && RELAY_PDS_PER_HOUR_LIMIT=1000000
[ "$RELAY_PDS_PER_DAY_LIMIT" == "" ] && RELAY_PDS_PER_DAY_LIMIT=1000000

error=
pds_exists="$(wget -qO- --header="Authorization: Basic ${RELAY_ADMIN_AUTH}" "https://$relayFQDN/admin/pds/list"| jq --arg host "$pdsFQDN" '.[] | select(.Host == $host)')"
if [ "$pds_exists" == "" ]
  then
    show_warning --oneline "PDS not registered" "so will request crawl"
    wget -O- --method=POST --body-data="{\"hostname\": \"$pdsFQDN\"}" --header="Content-Type: application/json" --header="Authorization: Basic ${RELAY_ADMIN_AUTH}" "https://$relayFQDN/admin/pds/requestCrawl"
  fi

previous_limit="$(wget -qO- --header="Authorization: Basic ${RELAY_ADMIN_AUTH}" "https://$relayFQDN/admin/subs/perDayLimit"| jq -r .limit)"
if [ "$previous_limit" == "$RELAY_SUBS_PER_DAY" ]
  then
    show_info --oneline "Relay crawl limit" "already set to $RELAY_SUBS_PER_DAY; not adjusting"
  else
    wget -qO- --method=POST --header="Authorization: Basic ${RELAY_ADMIN_AUTH}" "https://$relayFQDN/admin/subs/setPerDayLimit?limit=$RELAY_SUBS_PER_DAY"
    new_limit="$(wget -qO- --header="Authorization: Basic ${RELAY_ADMIN_AUTH}" "https://$relayFQDN/admin/subs/perDayLimit" | jq -r .limit)"
    if [ "$new_limit" == "" ]; then
      show_error "Error setting new limit:" "will show debug output from querying it"
      show_info "relay admin key length" "$(echo -n ${RELAY_ADMIN_KEY} | wc -c)"
      wget -vO- --header="Authorization: Basic ${RELAY_ADMIN_AUTH}" "https://$relayFQDN/admin/subs/perDayLimit"
      error=1
    else
      show_info --oneline "Relay crawl limit" "was $previous_limit, adjusted to $new_limit"
    fi
  fi

function get_pds_limits() {
  wget -qO- --header="Authorization: Basic ${RELAY_ADMIN_AUTH}" "https://$relayFQDN/admin/pds/list"| jq --arg host "$pdsFQDN" '.[] | select(.Host == $host) | {RateLimit, CrawlRateLimit, RepoLimit, HourlyEventLimit, DailyEventLimit}'
}

previous_limits="$(get_pds_limits)"
previous_repo_limit="$(echo "$previous_limits" | jq -r '.RepoLimit')"
previous_second_limit="$(echo "$previous_limits" | jq -r '.RateLimit')"
previous_hour_limit="$(echo "$previous_limits" | jq -r '.HourlyEventLimit')"
previous_day_limit="$(echo "$previous_limits" | jq -r '.DailyEventLimit')"
previous_crawl_limit="$(echo "$previous_limits" | jq -r '.CrawlRateLimit')"
if [[ "$previous_repo_limit" == "$RELAY_PDS_REPO_LIMIT" && "$previous_second_limit" == "$RELAY_PDS_PER_SECOND_LIMIT" && "$previous_hour_limit" == "$RELAY_PDS_PER_HOUR_LIMIT" && "$previous_day_limit" == "$RELAY_PDS_PER_DAY_LIMIT" && "$previous_crawl_limit" == "$RELAY_PDS_CRAWL_RATE_LIMIT" ]]
  then
    show_info --oneline "PDS limits" "already set to configured values; not adjusting"
  else
    adjusted_limits="$(echo "$previous_limits" | jq --arg repo_limit "$RELAY_PDS_REPO_LIMIT" --arg second_limit "$RELAY_PDS_PER_SECOND_LIMIT" --arg hour_limit "$RELAY_PDS_PER_HOUR_LIMIT" --arg day_limit "$RELAY_PDS_PER_DAY_LIMIT" --arg crawl_limit "$RELAY_PDS_CRAWL_RATE_LIMIT" \
            '.RepoLimit = ($repo_limit | tonumber) | .RateLimit = ($second_limit | tonumber) | .HourlyEventLimit = ($hour_limit | tonumber) | .DailyEventLimit = ($day_limit | tonumber) | .CrawlRateLimit = ($crawl_limit | tonumber)')"
    post_limits="$(echo "$adjusted_limits" | jq --arg host "$pdsFQDN" '{per_second: .RateLimit, crawl_rate: .CrawlRateLimit, per_hour: .HourlyEventLimit, per_day: .DailyEventLimit, repo_limit: .RepoLimit, host: $host}')"
    post_results="$(wget -qO- --method=POST --body-data="$post_limits" --header="Content-Type: application/json" --header="Authorization: Basic ${RELAY_ADMIN_AUTH}" "https://$relayFQDN/admin/pds/changeLimits")"
    post_success="$(echo "$post_results" | jq -r .success)"
    if [ "$post_success" == "true" ]; then
      show_info --oneline "relay limits changed" "will confirm"
    else
      show_warning --oneline "relay limit change error" "${post_results}"
    fi
    new_limits="$(get_pds_limits)"
    new_repo_limit="$(echo "$new_limits" | jq -r '.RepoLimit')"
    new_second_limit="$(echo "$new_limits" | jq -r '.RateLimit')"
    new_hour_limit="$(echo "$new_limits" | jq -r '.HourlyEventLimit')"
    new_day_limit="$(echo "$new_limits" | jq -r '.DailyEventLimit')"
    new_crawl_limit="$(echo "$new_limits" | jq -r '.CrawlRateLimit')"
    if [[ "$new_repo_limit" == "" || "$post_success" != "true" ]]; then
      show_error "Error setting new limits:" "will show debug output from querying it"
      show_info "relay admin key length" "$(echo -n ${RELAY_ADMIN_KEY} | wc -c)"
      wget -qO- --header="Authorization: Basic ${RELAY_ADMIN_AUTH}" "https://$relayFQDN/admin/pds/list" | jq
      error=1
    else
      show_info --oneline "PDS repo limit" "was $previous_repo_limit, now is $new_repo_limit"
      show_info --oneline "PDS per second limit" "was $previous_second_limit, now is $new_second_limit"
      show_info --oneline "PDS per hour limit" "was $previous_hour_limit, now is $new_hour_limit"
      show_info --oneline "PDS per day limit" "was $previous_day_limit, now is $new_day_limit"
      show_info --oneline "PDS crawl rate limit" "was $previous_crawl_limit, now is $new_crawl_limit"
    fi
  fi

if [ "$error" == "" ]; then exit 0 ; else exit "$error" ; fi

