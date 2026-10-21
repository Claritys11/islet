#!/bin/sh
# Live check against the running Islet: `sh tests/finder-live.sh`.
set -u
fail() { echo "FAIL: $*"; exit 1; }
out=$(islet find --print isw 2>&1) || fail "islet find --print isw: $out"
first=$(printf '%s\n' "$out" | head -n 1)
case "$first" in
*"~/Projects/islet-windows") ;;
*) fail "first result for isw: '$first'" ;;
esac
islet find --print '!nothing' >/dev/null 2>&1 || fail "operator query crashed"
islet find --print "a'b \$c" >/dev/null 2>&1 || fail "quote query crashed"
echo PASS
