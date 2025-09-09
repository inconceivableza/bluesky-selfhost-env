#!/usr/bin/env bash

echo "rDir:   ${rDir}"

d_=${rDir}/ozone
pushd ${d_}

sed -i.bak -E 's#"@atproto/api": "([0-9\.]+)"#"@atproto/api": "^\1"#'     package.json
sed -i.bak -E 's#"@atproto/ozone": "([0-9\.]+)"#"@atproto/ozone": "^\1"#' service/package.json

popd
