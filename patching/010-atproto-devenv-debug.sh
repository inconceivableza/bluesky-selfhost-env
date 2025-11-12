#!/usr/bin/env bash

echo "rDir:   ${rDir}"
echo "pDir:   ${pDir}"

d_=${rDir}/social-app/submodules/atproto
p1_=${pDir}/010-atproto-devenv-debug.diff
p2_=${pDir}/010-atproto-devenv-debug-others.diff

echo "applying patch: under ${d_} for ${p1_} ${p2_}"

pushd ${d_}
patch -p1 < ${p1_}
patch -p1 < ${p2_}
git add packages/dev-env/src/debug.ts
popd
