#!/bin/sh
# Live check against the running Islet: `sh tests/today-live.sh`.
set -u
fail() { echo "FAIL: $*"; exit 1; }

# Wait for the first load (Notion and Dank Calendar answer in a few seconds).
i=0
while :; do
    out=$(islet today status 2>&1) || fail "islet today status: $out"
    case "$out" in *"loading"*) ;; *) break ;; esac
    i=$((i + 1))
    [ $i -lt 40 ] || fail "still loading: $out"
    sleep 0.5
done
echo "$out"
echo "$out" | grep -q "dcal: ok" || fail "dcal not ok"
echo "$out" | grep -q "notion: ok" || fail "notion not ok"
echo "$out" | grep -q "timetable: Jadwal Pelajaran" || fail "wrong timetable"
echo "$out" | grep -q "tasks db: Tasks" || fail "wrong tasks database"
echo "$out" | grep -Eq "lessons today: [0-9]+" || fail "no lesson count"
echo "$out" | grep -Eq "lessons: 23" || fail "expected 23 timetable rows"
echo PASS
