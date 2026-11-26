#!/bin/bash
# Regenerates addons/partii/THIRD-PARTY-NOTICES.txt (the browser half's notices) with Partii's own
# generator: node <partii monorepo>/platform/scripts/licenses.mjs --cargo ... (reads only; writes --out).
#   PARTII_MONOREPO=<path to the partii monorepo> tools/web-notices.sh
# tools/engine-notices/Cargo.toml pins partii-net at the same rev as platform/crates/partii-engine,
# without the "native" feature (the web build). cargo metadata covers every target, so the list is a
# superset of what the wasm links. partii-sdk.js bundles only Partii's own web SDK (no npm packages).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${PARTII_MONOREPO:?path to the partii monorepo}"
T=$(mktemp)
node "$PARTII_MONOREPO/platform/scripts/licenses.mjs" --cargo tools/engine-notices/Cargo.toml --root partii-engine-web \
  --out "$T" --title "partii-engine.wasm (Partii rooms engine, web build)" >/dev/null
{
  cat <<'HEAD'
Third-party notices: Partii for Godot (addons/partii)

partii.gd, net.gd, plugin.gd and partii-sdk.js are Partii's own code (MIT OR Apache-2.0, see
LICENSE-MIT and LICENSE-APACHE). partii-sdk.js bundles Partii's web SDK and no third-party packages.

partii-engine.js and partii-engine.wasm are Partii's rooms engine (partii-net,
github.com/PartiiGames/partii-sdk) built for the web. They include the Rust crates listed below.
The list covers every target the crates build for, so it may name a few the web build doesn't link.

The native binaries in the GitHub release zip (addons/partii/bin/) have their own list in that
zip's THIRD-PARTY.md.

HEAD
  cat "$T"
} > addons/partii/THIRD-PARTY-NOTICES.txt
rm -f "$T"
echo "wrote addons/partii/THIRD-PARTY-NOTICES.txt ($(grep -cE '^[a-z0-9_-]+ [0-9][^ ]* \(' addons/partii/THIRD-PARTY-NOTICES.txt) crates)"
