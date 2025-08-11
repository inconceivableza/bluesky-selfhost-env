#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"
source_env

show_heading "Checking DNS" configuration
public_ip=`curl -s api.ipify.org/`
echo "Expected IP address is $public_ip"
if [ "$CADDY_DNS_RESOLVER" == "" ]
  then
    show_info "Will check DNS" "only against default from OS"
  else
    show_info "Will check DNS" "against default from OS as well as $CADDY_DNS_RESOLVER"
  fi

if [ "$os" == "macos" ]
  then
    function dns_lookup() {
      if [ $# -ge 2 ]
        then
          dig +short -t a -q "$1" "@$2" | tail -n 1
        else
          echo dscacheutil >&2
          dscacheutil -q host -a name "$1" | grep 'ip_address:' | sed 's/^[a-z_]*: //' | tail -n 1
        fi
    }
  else
    function dns_lookup() {
      if [ $# -ge 2 ]
        then
          dig +short -t a -q "$1" "@$2" | tail -n 1
        else
          dig +short -t a -q "$1" | tail -n 1
        fi
    }
  fi

# TODO: requires bind9-dnsutils
function check_dns_maps_to_here() {
  check_domain="$1"
  echo -n "Checking DNS for $check_domain... "
  if [ "$CADDY_DNS_RESOLVER" != "" ]
    then
      resolved_ip="`dns_lookup "$1" "$CADDY_DNS_RESOLVER" | tail -n 1`"
      failure=
      if [ "$resolved_ip" == "$public_ip" ]
        then
          echo -n "$resolved_ip "
          show_success_n
          echo -n " "
        else
          echo -n "$resolved_ip != $public_ip "
          show_failure
          return 1
        fi
    fi
  resolved_ip="`dns_lookup "$1" | tail -n 1`"
  if [ "$resolved_ip" == "$public_ip" ]
    then
      echo -n "$resolved_ip "
      show_success
      return 0
    else
      echo -n "$resolved_ip != $public_ip "
      show_failure
      return 1
    fi
}

check_dns_maps_to_here "${DOMAIN}"|| { show_error "Main Domain DNS is not configured:" "you will need to set this up yourself for ${DOMAIN}" ; exit 1 ; }
# this is to check there really is a wildcard domain configured
check_dns_maps_to_here "random-`pwgen 4`.${DOMAIN}" || { show_error "Wildcard DNS is not configured:" "you will need to set this up yourself for *.${DOMAIN}" ; exit 1 ; }

check_dns_maps_to_here "${socialappFQDN}"|| { show_error "Social Domain DNS is not configured:" "you will need to set this up yourself for ${socialappFQDN}" ; exit 1 ; }

check_dns_maps_to_here "${pdsFQDN}"|| { show_error "PDS Domain DNS is not configured:" "you will need to set this up yourself for ${pdsFQDN}" ; exit 1 ; }
# this is to check there really is a wildcard domain configured
check_dns_maps_to_here "random-`pwgen 4`.${pdsFQDN}" || { show_error "PDS Wildcard DNS is not configured:" "you will need to set this up yourself for *.${pdsFQDN}" ; exit 1 ; }

