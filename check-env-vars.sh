#!/usr/bin/env bash

script_path="`realpath "$0"`"
script_dir="`dirname "$script_path"`"
. "$script_dir/utils.sh"

show_heading "Searching repos" "for environment variables"
show_info "Finding relevant files" "within repos"
_files=`find repos -type f | grep -v -e '/.git' -e /__  -e /tests/ -e _test.go -e /interop-test-files  -e /testdata/ -e /testing/ -e /jest/ -e /node_modules/ -e /dist/ | sort -u -f`

show_info "Finding environment variables" "within files"
# for javascripts families from process.env.ENVNAME
grep -R process.env ${_files} \
  | cut -d : -f 2- | sed 's/.*process\.//' | grep '^env\.' | sed 's/^env\.//' \
  | sed -r 's/(^[A-Za-z_0-9\-]+).*/\1/' | sort -u -f \
  > /tmp/vars-js1.txt
show_info "Found in JS files (1):" "`wc -l < /tmp/vars-js1.txt` vars"

# for javascripts families from envXXX('MORE_ENVNAME'), refer atproto/packages/common/src/env.ts for envXXX
grep -R -e envStr -e envInt -e envBool -e envList ${_files} \
  | cut -d : -f 2- \
  | grep -v -e ^import -e ^export -e ^function  \
  | sed "s/\"/'/g" \
  | grep "'" | awk -F"'" '{print $2}' | sort -u -f \
  > /tmp/vars-js2.txt
show_info "Found in JS files (2):" "`wc -l < /tmp/vars-js2.txt` vars"

# for golang  from EnvVar(s): []string{"ENVNAME", "MORE_ENVNAME"}
grep -R EnvVar ${_files} \
  | cut -d : -f 3- | sed -e 's/.*string//' -e 's/[,"{}]//g' \
  | tr ' ' '\n' | grep -v ^$ | sort -u -f \
  > /tmp/vars-go.txt
show_info "Found in Go files:" "`wc -l < /tmp/vars-go.txt` vars"

# for docker-compose from services[].environment
echo {$_files} \
  | tr ' ' '\n' | grep -v ^$ | grep -e .yaml$ -e .yml$ | grep compose \
  | xargs yq -y .services[].environment | grep -v ^--- | sed 's/^- //' \
  | sed 's/: /=/' | sed "s/'//g" \
  | sort -u -f \
  | awk -F= '{print $1}' | sort -u -f \
  > /tmp/vars-compose.txt
show_info "Found in docker-compose files:" "`wc -l < /tmp/vars-compose.txt` vars"

# get unique lists
cat /tmp/vars-js1.txt /tmp/vars-js2.txt /tmp/vars-go.txt /tmp/vars-compose.txt | sort -u -f > /tmp/envs.txt
show_info "Total variables found:" "`wc -l < /tmp/envs.txt`"

show_info "Relevant variables" "for mapping"
# pick env vars related to mapping {URL, ENDPOINT, DID, HOST, PORT, ADDRESS}
cat /tmp/envs.txt  | grep -e URL -e ENDPOINT -e DID -e HOST -e PORT -e ADDRESS

