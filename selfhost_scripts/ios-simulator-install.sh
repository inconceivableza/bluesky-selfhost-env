#!/bin/bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`/.."
. "$script_dir/utils.sh"

app_tgz="$1"
[[ "$app_tgz" != "" && -f "$app_tgz" ]] || { show_error "Please provide simulator bundle" "this should be a .tgz file produced by the expo build process" ; exit 1 ; }
app_dirname="$(basename $app_tgz .tgz)"
app_tgz="$(realpath "$app_tgz")"
show_info --oneline "Extracting $app_dirname" "to temporary directory from $app_tgz"
tmpdir="$script_dir/ios-builds/tmp/$app_dirname"
mkdir -p $tmpdir
cd $tmpdir
tar xzf "$app_tgz"
for app in $(find . -name "*.app" -type d -depth 2 | grep -v ".appex" | grep -v "Frameworks" | grep -v "AppClips")
  do
    app_name="$(basename "$app" .app)"
    show_heading "Installing $app_name" "on iOS simulator"
    xcrun simctl install booted $app
  done
cd $script_dir
show_info --oneline "Cleaning up" "by removing temporary directory $tmpdir"
rm -r $tmpdir

