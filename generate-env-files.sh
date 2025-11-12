#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

show_heading "Creating environments" "for social-app from production, development and test environments"
$script_dir/selfhost_scripts/generate-social-env.py -P -D || { show_error "Error generating social-app environment" "which is required for build" ; exit 1 ; }
$script_dir/selfhost_scripts/generate-social-env.py -T || show_warning "Error generating social-app test environment" "so build will not contain it"
$script_dir/selfhost_scripts/generate-social-env.py -P -p development -o repos/social-app/bskyembed/ -t selfhost_scripts/social-env-embedr.mustache --no-branding || { show_error "Error generating social-app embedr environment" "which is required for build" ; exit 1 ; }
$script_dir/selfhost_scripts/generate-google-services-json.py -PDTV || show_warning "Error generating google services for all build environments"

show_heading "Creating env-content files" "for bsky appview from production, development and test environments"
$script_dir/selfhost_scripts/generate-appview-env.py -PD -o repos/social-app/conf/ -o repos/atproto/services/bsky/ || show_error "Error generating production/development bsky appview env-content files"
$script_dir/selfhost_scripts/generate-appview-env.py -T -o repos/social-app/conf/ -o repos/atproto/services/bsky/ || show_warning "Error generating test/staging bsky appview env-content files"

