#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"
source_env

include_haproxy=""
[ "$haproxyFORWARD" == "true" ] && include_haproxy=haproxy

show_heading "Fetching unbranded containers" "for required services with generic builds"
# Get all services defined in docker-compose.yaml
all_services="$(yq '.services | keys | .[]' docker-compose.yaml) $include_haproxy"

# Categorize services using utils.sh definitions
branded_services=""
custom_services=""
unbranded_services=""
nondocker_services=""

for service in $all_services; do
    if echo "$REBRANDED_SERVICES" | grep -q "\b$service\b"; then
        branded_services="$branded_services $service"
    elif echo "$CUSTOM_SERVICES" | grep -q "\b$service\b"; then
        custom_services="$custom_services $service"
    elif [ "$service" == "haproxy" ]; then
        nondocker_services="$service"
    else
        unbranded_services="$unbranded_services $service"
    fi
done

echo "branded services: $branded_services"
echo "custom services: $custom_services" 
echo "unbranded services: $unbranded_services"
make docker-pull-unbranded unbranded_services="${unbranded_services//$'\n'/ }" || { show_error "Fetching Containers failed:" "Please see error above" ; exit 1 ; }

show_heading "Deploy required containers" "(database, caddy etc)"
make docker-start || { show_error "Required Containers failed:" "Please see error above" ; exit 1 ; }

function macos_check_haproxy_config() {
  haproxy_brew_json="$(brew services info haproxy --json | jq '.[0]')"
  haproxy_cmdline="$(echo "$haproxy_brew_json" | jq -r .command)"
  cfg_next=
  haproxy_config=
  link_target="$(readlink -f $script_dir/config/haproxy.cfg)"
  for word in $haproxy_cmdline; do
    [ "$word" == "-f" ] && cfg_next=true
    [ "$cfg_next" == "true" ] && haproxy_config="$word"
  done
  [ "$haproxy_config" == "" ] && { show_warning "Error finding haproxy config file" "from cmdline; will not configure haproxy" ; return 1 ; }
  if [ -h "$haproxy_config" ]; then
    current_target="$(readlink -f "$haproxy_config")"
    [ "$current_target" == "$link_target" ] && { show_info --oneline "haproxy configured correctly" "with symlink to $link_target" ; return 0 ; }
    show_warning "haproxy configured incorrectly" "with symlink to $current_target, not $link_target" ; return 1
  elif [ -e "$haproxy_config" ]; then
    show_warning "haproxy configured incorrectly:" "check $haproxy_config and remove if not needed, so this script can symlink to $link_target"
    return 1
  else
    show_info --oneline "creating haproxy config symlink" "from $haproxy_config to $link_target"
    ln -s "$link_target" "$haproxy_config"
    return 0
  fi
}

function macos_deploy_haproxy() {
  show_heading "Deploying haproxy" "service as frontend for caddy"
  macos_check_haproxy_config
  brew services start haproxy
}

[ "$nondocker_services" == "haproxy" ] && {
  if [ "$os" == macos ]; then macos_deploy_haproxy
  else show_warning "haproxy is configured" "but starting it is not yet automated on your os ($os)"
  fi
}

show_heading "Checking certificates" "which may need to refresh with letsencrypt"
domains_to_test="${DOMAIN} ${socialappFQDN} ${cardFQDN} ${embedFQDN} ${linkFQDN} ${pdsFQDN} ${bgsFQDN} ${bskyFQDN} ${feedgenFQDN} ${ipFQDN} ${jetstreamFQDN} ${ozoneFQDN} ${palomarFQDN} ${plcFQDN} ${publicApiFQDN} ${apiFQDN} ${gifFQDN} ${videoFQDN}"
num_checks=0
while [[ "$domains_to_test" != "" ]]
  do
    [ "$num_checks" -gt 0 ] && {
      show_info --oneline "Sleeping before retesting" "for domains $domains_to_test..."
      sleep 10
    }
    show_info "Testing certificates" "for domains $domains_to_test"
    error_domains=
    for domain in $domains_to_test
      do
        show_info --oneline "Testing" "$domain"
        { echo 'HEAD / HTTP/1.0' ; echo ; } | openssl s_client -connect ${domain}:443 >/dev/null 2>&1 || {
          show_warning --oneline "Connection error" "for domain $domain"
          error_domains="$error_domains $domain"
        }
      done
    domains_to_test="$error_domains"
    num_checks=$((num_checks+1))
    [ "$num_checks" -gt "3" ] && { show_error "Certificates not successful" "after $num_checks_tries" ; break ; }
  done

show_heading "Deploy bluesky containers" "(plc, bgs, appview, pds, ozone, ...)"
make docker-start-bsky || { show_error "BlueSky Containers failed:" "Please see error above" ; exit 1 ; }

show_info --oneline "Adjusting relay settings" "to allow PDS crawling"
wait_for_container bgs
"$script_dir/selfhost_scripts/adjust-bgs-limits.sh" || { show_warning "Error adjusting relay settings" "this could prevent the PDS from being crawled; check..." ; }

show_heading "Wait for startup" "of social app"
# could also wait for Sbsky ?=pds bgs bsky social-app palomar
# this requires a health check to be defined on the container
wait_for_container social-app


