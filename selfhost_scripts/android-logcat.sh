#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="$(cd `dirname "$script_path"`/.. ; pwd)"
. "$script_dir/utils.sh"
source_env

cd "$script_dir"

branding_file=$REBRANDING_DIR/branding.yml
package_id=$(yq -r e '.code.web_package_id' $branding_file)

build_profile=

if [ "$#" -gt 0 ]; then
  [[ "${1/-/}" == "$1" ]] && [ "$build_profile" == "" ] && { build_profile="$1" ; shift 1 ; }
fi

package_suffix=
if [[ "$build_profile" == "" ]]; then
  package_suffix=
elif [[ "$build_profile" == "production" ]]; then
  package_suffix=
elif [[ "$build_profile" == "development" ]]; then
  package_suffix=.dev
else
  package_suffix=".$build_profile"
fi

check_adb_device() {
    # Get the output of 'adb devices' and filter for "device" or "emulator" status
    # The 'awk' command extracts the second column (status)
    # and 'grep -q' checks for "device" silently, returning 0 if found
    adb_online="$(adb devices | awk '{print $2}')"
    if echo "$adb_online" | grep "device" >/dev/null; then
        show_info --oneline "Device found" "and reachable through adb"
        return 0
    elif echo "$adb_online" | grep "emulator" >/dev/null; then
        show_info --oneline "Emulator found" "and reachable through adb"
        return 0
    else
        show_warning "No device or emulator found" "through adb"
        return 1
    fi
}

show_info --oneline "Checking device" "reachable through adb"
check_adb_device || exit 1

show_info --oneline "Finding pid" "for $package_id$package_suffix"
pid=$(adb shell pidof $package_id$package_suffix)

[[ "$pid" == "" ]] && { show_error "No process found" "for $package_id$package_suffix" ; exit 1; }

adb logcat --pid="$pid" ReactNative:V ReactNativeJS:V *:I "$@"

