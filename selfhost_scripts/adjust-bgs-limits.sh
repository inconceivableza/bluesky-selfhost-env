#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="$(cd `dirname "$script_path"`/.. ; pwd)"
. "$script_dir/utils.sh"
source_env

BGS_SECRETS_FILE="$script_dir/config/bgs-secrets.env"
make $BGS_SECRETS_FILE
. $BGS_SECRETS_FILE

[ "$bgsFQDN" == "" ] && { show_warning "Couldn't find bgs domain" "from bgsFQDN environment; please check $params_file" >&2 ; exit 1 ; }
[ "$BGS_ADMIN_KEY" == "" ] && { show_warning "Couldn't find bgs admin key" "from environment or secrets file; please check BGS_ADMIN_KEY in $params_file and $script_dir/config/secrets-passwords.env" >&2 ; exit 1 ; }

# can pass this on the commandline or set it in the .env
[ "$#" -gt 0 ] && {
   BGS_SUBS_PER_DAY="$1"
   shift 1
}
[ "$BGS_SUBS_PER_DAY" == "" ] && BGS_SUBS_PER_DAY=500

[ "$#" -gt 0 ] && {
   BGS_PDS_REPO_LIMIT="$1"
   shift 1
}
[ "$BGS_PDS_REPO_LIMIT" == "" ] && BGS_PDS_REPO_LIMIT=1000000
[ "$BGS_PDS_CRAWL_RATE_LIMIT" == "" ] && BGS_PDS_CRAWL_RATE_LIMIT=10
[ "$BGS_PDS_PER_SECOND_LIMIT" == "" ] && BGS_PDS_PER_SECOND_LIMIT=100
[ "$BGS_PDS_PER_HOUR_LIMIT" == "" ] && BGS_PDS_PER_HOUR_LIMIT=1000000
[ "$BGS_PDS_PER_DAY_LIMIT" == "" ] && BGS_PDS_PER_DAY_LIMIT=1000000

error=
pds_exists="$(wget -qO- --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/pds/list"| jq --arg host "$pdsFQDN" '.[] | select(.Host == $host)')"
if [ "$pds_exists" == "" ]
  then
    show_warning --oneline "PDS not registered" "so will request crawl"
    wget -qO- --method=POST --body-data="{\"hostname\": \"$pdsFQDN\"}" --header="Content-Type: application/json" --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/pds/requestCrawl"
  fi

previous_limit="$(wget -qO- --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/subs/perDayLimit"| jq -r .limit)"
if [ "$previous_limit" == "$BGS_SUBS_PER_DAY" ]
  then
    show_info --oneline "Relay crawl limit" "already set to $BGS_SUBS_PER_DAY; not adjusting"
  else
    wget -qO- --method=POST --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/subs/setPerDayLimit?limit=$BGS_SUBS_PER_DAY"
    new_limit="$(wget -qO- --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/subs/perDayLimit" | jq -r .limit)"
    if [ "$new_limit" == "" ]; then
      show_error "Error setting new limit:" "will show debug output from querying it"
      show_info "bgs admin key length" "$(echo -n ${BGS_ADMIN_KEY} | wc -c)"
      wget -vO- --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/subs/perDayLimit"
      error=1
    else
      show_info --oneline "Relay crawl limit" "was $previous_limit, adjusted to $new_limit"
    fi
  fi

function get_pds_limits() {
  wget -qO- --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/pds/list"| jq --arg host "$pdsFQDN" '.[] | select(.Host == $host) | {RateLimit, CrawlRateLimit, RepoLimit, HourlyEventLimit, DailyEventLimit}'
}

previous_limits="$(get_pds_limits)"
previous_repo_limit="$(echo "$previous_limits" | jq -r '.RepoLimit')"
previous_second_limit="$(echo "$previous_limits" | jq -r '.RateLimit')"
previous_hour_limit="$(echo "$previous_limits" | jq -r '.HourlyEventLimit')"
previous_day_limit="$(echo "$previous_limits" | jq -r '.DailyEventLimit')"
previous_crawl_limit="$(echo "$previous_limits" | jq -r '.CrawlRateLimit')"
if [[ "$previous_repo_limit" == "$BGS_PDS_REPO_LIMIT" && "$previous_second_limit" == "$BGS_PDS_PER_SECOND_LIMIT" && "$previous_hour_limit" == "$BGS_PDS_PER_HOUR_LIMIT" && "$previous_day_limit" == "$BGS_PDS_PER_DAY_LIMIT" && "$previous_crawl_limit" == "$BGS_PDS_CRAWL_RATE_LIMIT" ]]
  then
    show_info --oneline "PDS limits" "already set to configured values; not adjusting"
  else
    adjusted_limits="$(echo "$previous_limits" | jq --arg repo_limit "$BGS_PDS_REPO_LIMIT" --arg second_limit "$BGS_PDS_PER_SECOND_LIMIT" --arg hour_limit "$BGS_PDS_PER_HOUR_LIMIT" --arg day_limit "$BGS_PDS_PER_DAY_LIMIT" --arg crawl_limit "$BGS_PDS_CRAWL_RATE_LIMIT" \
            '.RepoLimit = ($repo_limit | tonumber) | .RateLimit = ($second_limit | tonumber) | .HourlyEventLimit = ($hour_limit | tonumber) | .DailyEventLimit = ($day_limit | tonumber) | .CrawlRateLimit = ($crawl_limit | tonumber)')"
    post_limits="$(echo "$adjusted_limits" | jq --arg host "$pdsFQDN" '{per_second: .RateLimit, crawl_rate: .CrawlRateLimit, per_hour: .HourlyEventLimit, per_day: .DailyEventLimit, repo_limit: .RepoLimit, host: $host}')"
    post_results="$(wget -qO- --method=POST --body-data="$post_limits" --header="Content-Type: application/json" --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/pds/changeLimits")"
    post_success="$(echo "$post_results" | jq -r .success)"
    if [ "$post_success" == "true" ]; then
      show_info --oneline "bgs limits changed" "will confirm"
    else
      show_warning --oneline "bgs limit change error" "${post_results}"
    fi
    new_limits="$(get_pds_limits)"
    new_repo_limit="$(echo "$new_limits" | jq -r '.RepoLimit')"
    new_second_limit="$(echo "$new_limits" | jq -r '.RateLimit')"
    new_hour_limit="$(echo "$new_limits" | jq -r '.HourlyEventLimit')"
    new_day_limit="$(echo "$new_limits" | jq -r '.DailyEventLimit')"
    new_crawl_limit="$(echo "$new_limits" | jq -r '.CrawlRateLimit')"
    if [[ "$new_repo_limit" == "" || "$post_success" != "true" ]]; then
      show_error "Error setting new limits:" "will show debug output from querying it"
      show_info "bgs admin key length" "$(echo -n ${BGS_ADMIN_KEY} | wc -c)"
      wget -qO- --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/pds/list" | jq
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

