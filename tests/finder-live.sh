#!/bin/sh
# Live check against the running Islet: `sh tests/finder-live.sh`.
set -u
fail() { echo "FAIL: $*"; exit 1; }
CFG=islet
ipc() { qs -c "$CFG" ipc call finder "$@"; }

out=$(islet find --print isw 2>&1) || fail "islet find --print isw: $out"
first=$(printf '%s\n' "$out" | head -n 1)
case "$first" in
*"~/Projects/islet-windows") ;;
*) fail "first result for isw: '$first'" ;;
esac
islet find --print '!nothing' >/dev/null 2>&1 || fail "operator query crashed"
islet find --print "a'b \$c" >/dev/null 2>&1 || fail "quote query crashed"

# Nothing typed: answers (the recent list) instead of waiting forever.
islet find --print "" >/dev/null 2>&1 || fail "empty query never finished"

# A search started while another runs: the newer one's results, not an
# early empty answer.
ipc search "lyrics" >/dev/null
ipc search "isw" >/dev/null
i=0
while [ $i -lt 50 ]; do
    r=$(ipc results "isw")
    [ "$r" != pending ] && break
    sleep 0.1
    i=$((i + 1))
done
case "$(printf '%s\n' "$r" | head -n 1)" in
*"~/Projects/islet-windows") ;;
*) fail "after a quick second search: '$(printf '%s' "$r" | head -n 1)'" ;;
esac

# Acting before the results are in waits for them (Enter right after typing).
# The clipboard is put back afterwards, whatever kind of content it held.
clip=$(mktemp)
type=$(wl-paste --list-types 2>/dev/null | head -n 1)
[ -n "$type" ] && wl-paste --no-newline --type "$type" > "$clip" 2>/dev/null
ipc search "lyrics" >/dev/null
sleep 0.5
islet find --copy isw >/dev/null 2>&1 || fail "islet find --copy"
sleep 1
got=$(wl-paste -n 2>/dev/null)
if [ -n "$type" ]; then wl-copy --type "$type" < "$clip"; fi
rm -f "$clip"
[ "$got" = "$HOME/Projects/islet-windows" ] || fail "--copy isw copied '$got'"
echo PASS
