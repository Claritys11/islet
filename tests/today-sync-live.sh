#!/bin/sh
# Live sync check against Dank Calendar's local "Islet test" calendar:
#   TEST_CAL=<calendar id> sh tests/today-sync-live.sh
# Writes GCal IDs into the real Tasks rows (ask the user first). Puts the
# target calendar setting back afterwards.
set -u
fail() { echo "FAIL: $*"; islet set todayCalendar "$saved" >/dev/null; exit 1; }
: "${TEST_CAL:?set TEST_CAL to the test calendar id}"
saved=$(islet get todayCalendar)
count() { dcal ipc events.list from="$(date -d '-60 days' -Iseconds)" to="$(date -d '+400 days' -Iseconds)" query=islet-notion --json | python3 -I -c "
import json, sys
d = json.load(sys.stdin); d = d.get('events', d) if isinstance(d, dict) else d
ids = {e['id'] for e in d if e['calendarId'] == sys.argv[1]}
rec = {e['id'] for e in d if e['calendarId'] == sys.argv[1] and e.get('recurrence')}
print(len(rec), len(ids - rec))" "$TEST_CAL"; }

islet set todayCalendar "$TEST_CAL" >/dev/null
sleep 2
islet today reload >/dev/null; sleep 6
p=$(islet today preview) || fail "preview: $p"
echo "preview: $p"
echo "$p" | grep -qE "buat 26 event|create 26 events" || fail "expected 26 new events (23 lessons + 3 tasks)"
[ "$(count)" = "0 0" ] || fail "preview wrote to the calendar: $(count)"
islet today confirm >/dev/null
islet today sync >/dev/null
i=0
while [ $i -lt 60 ]; do
    s=$(islet today status | sed -n 's/^sync: //p')
    case "$s" in "done"*) break ;; esac
    sleep 1; i=$((i + 1))
done
echo "sync: $s"
[ "$(count)" = "23 3" ] || fail "calendar has $(count) (series, singles), want 23 3"
islet today status | grep -q "^linked: 26" || fail "not every row linked: $(islet today status | grep linked)"
p2=$(islet today preview)
echo "second preview: $p2"
echo "$p2" | grep -qE "^(tidak ada perubahan|no changes)" || fail "second sync would change: $p2"
islet set todayCalendar "$saved" >/dev/null
echo PASS
