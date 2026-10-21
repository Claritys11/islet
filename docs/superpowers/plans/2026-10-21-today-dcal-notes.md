# Dank Calendar (dcal 1.6.1) — formats for Islet's sync

Probed on 2026-10-21 against a local test account ("Islet test", `local:dcal-test`, calendar
"Personal" `bf7073aa-3574-4e9e-adf9-b8e025e79d5f`, stored in `~/.local/state/islet/dcal-test`).

## Calling
- `dcal ipc <method> key=value … --json`. Values are separate argv words, no shell quoting needed.
- **Success:** JSON on stdout, exit 0.
- **Failure:** exit 1. The error is on stderr, as `Error: ipc error: <message>` followed by the usage
  text and ` ERROR  go: ipc error: <message>`. For example `ErrNotFound: event not found`, or
  `start must be RFC3339`. Islet shows the `<message>`.

## Reading
- `accounts.list` gives `[{id, kind ("google"|"local"…), displayName, needsReauth, authError}]`.
  `healthy` = a Google account with `needsReauth === false` and `authError === ""`.
- `calendars.list` gives `[{id, name, accountId, accountKind, accountName, readOnly, hidden,
  supportedComponents, …}]`. A calendar is writable when `!readOnly` and `supportedComponents` is null
  or contains `VEVENT`.
- **`events.list from= to= [query=] --json`:**
  - It returns **`{"events": [...]}`**.
  - Each event is `{id, uid, recurringId, calendarId, summary, description, location, start, end (UTC
    RFC3339), allDay, status, recurrence?: {rrule: ["RRULE:…"]}, …}`.
  - **Recurring series are expanded:** one item per occurrence in the window. All occurrences share the
    series `id` and `uid`. The first (master) has `recurringId === ""`; later ones have
    `recurringId === uid`. `recurrence` is present on every occurrence.
  - **Collapsing to series:** group by `id`. Take the item with `recurringId === ""`, or else the
    earliest. Any occurrence gives the weekday and times.
  - **`query=` matches the description too.** `query=islet-notion` returns only Islet's tagged events,
    so list with a wide window (from 60 days ago to a year ahead) to see all of Islet's task events.

## Writing
- `events.create calendarId= summary= start= end= description= [allDay=true] [recurrence=…]` returns
  the created event (the same shape as a list item). **The new id is `.id`.**
- **`recurrence=RRULE:FREQ=WEEKLY;BYDAY=TU`:** one plain string. A JSON list string is stored
  literally and is wrong.
- **All-day events** must still use RFC3339. dcal keeps the **date**: `start=2026-10-24T00:00:00+07:00`
  is stored as `2026-10-24T00:00:00Z`. Send `YYYY-MM-DDT00:00:00Z` for the date and the next date for
  `end`; read the date as `start.slice(0,10)`.
- `events.update id= [summary= start= end= description= allDay= recurrence=]` returns the updated
  event.
  - **Moving a series:** update `start` and `end` (the first occurrence's times). All occurrences
    move.
  - **Ending a series:** `recurrence=RRULE:FREQ=WEEKLY;BYDAY=TU;UNTIL=20261028T165959Z`. Later
    occurrences disappear.
  - `occurrenceStart=` with new times **shifts the whole series** by that delta; it doesn't move one
    occurrence. Islet never uses it.
- `events.delete id=` returns `{"deleted": true}`.

## Not probed
- Google-made single-occurrence exceptions: whether they appear as separate items or under the series
  id. Islet's collapse prefers the master (`recurringId === ""`), and any occurrence with a different
  time counts only if no master is in the window.
- `subscribe` streaming. Islet polls every few minutes instead.
