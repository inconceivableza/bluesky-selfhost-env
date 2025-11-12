#!/usr/bin/env bash

echo "rDir:   ${rDir}"
echo "pDir:   ${pDir}"

d_=${rDir}/social-app/submodules/atproto
p_=${pDir}/105-atproto-services-for-docker.diff

echo "applying patch: under ${d_} for ${p_}"

pushd ${d_}
patch -p1 < ${p_}
popd
