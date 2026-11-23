#!/bin/sh
# Checks addons/partii/plugin.cfg matches the Asset Library listing (name, author, version) and that
# the library's zip holds only addons/. Run: sh tools/check-plugin-cfg.sh  (exit 1 on a mismatch).
# Bump EXPECT_VERSION with each release.
set -eu
cd "$(dirname "$0")/.."
CFG=addons/partii/plugin.cfg
EXPECT_VERSION="${EXPECT_VERSION:-0.3.0}"
fail=0
check() {
  got=$(sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$CFG")
  if [ "$got" = "$2" ]; then echo "ok   $1=\"$got\""; else echo "FAIL $1: got \"$got\", want \"$2\""; fail=1; fi
}
[ -f "$CFG" ] || { echo "FAIL: $CFG missing"; exit 1; }
check name "Partii"
check author "Partii Games"
check version "$EXPECT_VERSION"
check script "plugin.gd"
for f in addons/partii/plugin.gd addons/partii/partii.gd addons/partii/partii-sdk.js icon.png LICENSE; do
  [ -f "$f" ] || { echo "FAIL: $f missing"; fail=1; }
done
# The library's zip is GitHub's archive of the commit: it must hold only addons/ (.gitattributes).
if git rev-parse HEAD >/dev/null 2>&1; then
  extra=$(git archive HEAD | tar -t | grep -v '^addons/' || true)
  if [ -n "$extra" ]; then echo "FAIL: the archive holds more than addons/:"; echo "$extra"; fail=1; else echo "ok   archive holds only addons/"; fi
fi
exit $fail
