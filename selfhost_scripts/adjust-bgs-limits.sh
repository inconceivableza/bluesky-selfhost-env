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
[ "$BGS_PDS_REPO_LIMIT" == "" ] && BGS_PDS_REPO_LIMIT=100000

error=

previous_limit="$(wget -qO- --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/subs/perDayLimit"| jq -r .limit)"
if [ "$previous_limit" == "$BGS_SUBS_PER_DAY" ]
  then
    show_info --oneline "Relay crawl limit" "already set to $BGS_SUBS_PER_DAY; not adjusting"
  else
    wget --method=POST --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/subs/setPerDayLimit?limit=$BGS_SUBS_PER_DAY"
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
previous_limit="$(echo "$previous_limits" | jq -r '.RepoLimit')"
if [ "$previous_limit" == "$BGS_PDS_REPO_LIMIT" ]
  then
    show_info --oneline "PDS repo limit" "already set to $BGS_PDS_REPO_LIMIT; not adjusting"
  else
    adjusted_limits="$(echo "$previous_limits" | jq --arg limit "$BGS_PDS_REPO_LIMIT" '.RepoLimit = ($limit | tonumber)')"
    post_limits="$(echo "$adjusted_limits" | jq --arg host "$pdsFQDN" '{per_second: .RateLimit, crawl_rate: .CrawlRateLimit, per_hour: .HourlyEventLimit, per_day: .DailyEventLimit, repo_limit: .RepoLimit, host: $host}')"
    post_results="$(wget -qO- --method=POST --body-data="$post_limits" --header="Content-Type: application/json" --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/pds/changeLimits")"
    post_success="$(echo "$post_results" | jq -r .success)"
    if [ "$post_success" == "true" ]; then
      show_info --oneline "bgs limits changed" "will confirm"
    else
      show_warning --oneline "bgs limit change error" "${post_results}"
    fi
    new_limits="$(get_pds_limits)"
    new_limit="$(echo "$new_limits" | jq -r '.RepoLimit')"
    if [[ "$new_limit" == "" || "$post_success" != "true" ]]; then
      show_error "Error setting new limit:" "will show debug output from querying it"
      show_info "bgs admin key length" "$(echo -n ${BGS_ADMIN_KEY} | wc -c)"
      wget -qO- --header="Authorization: Bearer ${BGS_ADMIN_KEY}" "https://$bgsFQDN/admin/pds/list" | jq
      error=1
    else
      show_info --oneline "PDS repo limit" "was $previous_limit, now is $new_limit"
    fi
  fi

if [ "$error" == "" ]; then exit 0 ; else exit "$error" ; fi

