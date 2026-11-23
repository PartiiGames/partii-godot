#!/bin/bash
# Bundles partii-godot.ts with the Partii web SDK into ../partii-sdk.js (committed; games ship it).
#   PARTII_SDK=<partii monorepo>/platform/sdk/ts/src ESBUILD=<esbuild binary> ./build.sh
set -euo pipefail
cd "$(dirname "$0")"
: "${PARTII_SDK:?the Partii web SDK source folder (platform/sdk/ts/src)}"
"${ESBUILD:-esbuild}" partii-godot.ts --bundle --format=iife --target=es2020 --minify --legal-comments=none \
  --alias:@partii/sdk="$PARTII_SDK" --outfile=../partii-sdk.js
echo "built ../partii-sdk.js ($(wc -c < ../partii-sdk.js) bytes)"
