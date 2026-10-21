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

# ── Tasks: add one, see it, tick it, then trash it (writes to the real Tasks
# database: run only with the user's OK).
[ "${TODAY_WRITE_TEST:-}" = 1 ] || { echo "(skipping the Notion write test; TODAY_WRITE_TEST=1 runs it)"; exit 0; }
name="Islet test task — hapus aku"
before=$(islet today status | sed -n 's/^tasks: //p')
islet today add "$name" >/dev/null || fail "islet today add"
sleep 4
after=$(islet today status | sed -n 's/^tasks: //p')
[ "$after" -eq $((before + 1)) ] || fail "tasks $before → $after after add"
islet today list | grep -q "$name" || fail "added task not listed"
islet today trash-test >/dev/null || fail "trash-test"
sleep 4
final=$(islet today status | sed -n 's/^tasks: //p')
[ "$final" -eq "$before" ] || fail "tasks $final after trash (want $before)"
echo PASS-WRITE
