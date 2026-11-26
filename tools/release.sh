#!/bin/bash
# Build the release zip: the addon with all native binaries (Q3: ship them all; nothing downloads native
# code at runtime). The repo stays source-only; binaries come from CI/macq builds.
#   tools/release.sh <version> <linux .so> <windows .dll> <macos universal .dylib (signed, notarized)>
# Writes dist/partii-godot-<version>.zip and dist/SHA256SUMS.
set -eo pipefail
V="$1"; SO="$2"; DLL="$3"; DYLIB="$4"
[ -n "$V" ] && [ -f "$SO" ] && [ -f "$DLL" ] && [ -f "$DYLIB" ] || { echo "usage: tools/release.sh <version> <so> <dll> <dylib>"; exit 2; }
cd "$(dirname "$0")/.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
A="$T/addons/partii"
mkdir -p "$A/bin"
git ls-files addons/partii | grep -v '^addons/partii/web/' | while read -r f; do mkdir -p "$T/$(dirname "$f")"; cp "$f" "$T/$f"; done
cp native/partii.gdextension "$A/"
cp "$SO" "$A/bin/libpartii_godot.linux.x86_64.so"
cp "$DLL" "$A/bin/partii_godot.windows.x86_64.dll"
cp "$DYLIB" "$A/bin/libpartii_godot.macos.universal.dylib"
cp LICENSE-MIT LICENSE-APACHE "$A/"
[ -f THIRD-PARTY.md ] && cp THIRD-PARTY.md "$A/"
echo "$V ($(git rev-parse --short HEAD))" > "$A/VERSION"
mkdir -p dist
Z="dist/partii-godot-$V.zip"; rm -f "$Z"
(cd "$T" && zip -qr -X "$OLDPWD/$Z" addons)
(cd "$A/bin" && shasum -a 256 *) > dist/SHA256SUMS.bin
(cd dist && shasum -a 256 "partii-godot-$V.zip") > dist/SHA256SUMS
sed 's#  #  addons/partii/bin/#' dist/SHA256SUMS.bin >> dist/SHA256SUMS && rm dist/SHA256SUMS.bin
unzip -l "$Z" | tail -n +4 | head -40
cat dist/SHA256SUMS
