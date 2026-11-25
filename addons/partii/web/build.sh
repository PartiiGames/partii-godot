#!/bin/bash
# Builds the browser half (committed; games ship it):
#   ../partii-sdk.js     partii-godot.ts with the Partii web SDK (always loaded)
#   ../partii-engine.js  the rooms engine's glue (engine/, from the monorepo's platform/sdk/engine-web);
#   ../partii-engine.wasm  its wasm. Both loaded only on the first room call.
#   PARTII_SDK=<partii monorepo>/platform/sdk/ts/src ESBUILD=<esbuild binary> ./build.sh
set -euo pipefail
cd "$(dirname "$0")"
: "${PARTII_SDK:?the Partii web SDK source folder (platform/sdk/ts/src)}"
E="${ESBUILD:-esbuild}"
"$E" partii-godot.ts --bundle --format=iife --target=es2020 --minify --legal-comments=none \
  --alias:@partii/sdk="$PARTII_SDK" --outfile=../partii-sdk.js
"$E" engine-entry.ts --bundle --format=iife --target=es2020 --minify --legal-comments=none \
  --log-override:empty-import-meta=silent --outfile=../partii-engine.js
cp engine/partii_engine_bg.wasm ../partii-engine.wasm
echo "built ../partii-sdk.js ($(wc -c < ../partii-sdk.js) bytes), ../partii-engine.js ($(wc -c < ../partii-engine.js)), ../partii-engine.wasm ($(wc -c < ../partii-engine.wasm))"
