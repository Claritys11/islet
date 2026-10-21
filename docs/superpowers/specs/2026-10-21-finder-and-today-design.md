# Islet: Finder (Listary-style search) and "Today" (Notion ⇄ Google Calendar)

Date: 2026-10-21 · Target release: Islet 1.6.0 (Linux, Quickshell)

Mockups the user approved (HTML fragments; open in a browser):
- `mockups/2026-10-21-finder-placement.html`: Finder, option **A** (chosen).
- `mockups/2026-10-21-today-tab.html`: the Today tab and the pill states.

Two features that ship in the same release but share no code. Build them in this order:
**Finder** (self-contained), then **Today**.

The user is a student on CachyOS with niri and DankMaterialShell. Islet's notch runs in **bar mode**:
the Islet Media DMS plugin is the pill, and the notch opens below it.

The user cares a lot about polish and about **easy configuration**. Every setting must be reachable
from the Settings window, findable through Settings search, and sensible by default. No hand-editing
of files should be needed.

---

## Part 1: Finder

### Why
The user often has to dig for a project folder or a specific file and then open it in Dolphin, the
terminal or VS Code. On Windows, Listary solves this. The user remembers **fragments or
abbreviations** of names, not exact names (for example "isw" for `islet-windows`). App launching is
**out of scope**, because DMS's Spotlight and application launcher already cover it.

### Decided by the user
- **Files and folders only.**
- **Where it appears:** the notch (or the DMS bar pill) grows into a search box (mockup "A"). There is
  no separate centred popup.
- **Fuzzy matching on fragments and abbreviations.**
- **Actions on a result:**
  - Enter: a folder opens in the file manager (Dolphin today, through the xdg default); a file opens
    in its default app.
  - Ctrl+T: open a terminal there (Ghostty today).
  - Ctrl+E: open in the editor (VS Code today).
  - Alt+Enter: open the folder that contains the file.
  - Ctrl+C: copy the path.

  The app behind each action is changeable in Settings.
- **Scope:** all of home, skipping hidden and junk folders. The exclusion list is editable in Settings.
- **Ranking:** project folders (those containing `.git`) and things the user opens often or recently
  rank higher. An empty query lists recent picks.
- **Keybind.** Proposal: `Mod+G`, which is free in the user's niri binds. Ask the user before editing
  `~/.config/niri/user-binds.kdl`, and validate with `niri validate`. `Mod+Space` belongs to DMS
  Spotlight and `Alt+Space` is taken.
- **Separable module.** The user plans to move Finder into its own repo later, so build it as a
  module with a narrow interface to the notch:
  - its own `Finder*.qml` files and helper script;
  - its own config keys under the `finder` prefix;
  - its own CLI subcommand and IPC target.

  The notch only hosts its view and gives it keyboard focus.

### Facts about the machine
- **Home size:** about 80k folders and 480k files.
- **`fd`:** a full scan of home takes about 0.3 s, which is fine for building an index but too slow per
  keystroke.
- **`plocate`:** installed, but it does **not** index `/home`. Baloo is off. Don't depend on either.
- **Other tools available:** `fd`, `fzf`, `rg`, `dolphin` (the xdg default for `inode/directory`),
  `ghostty`, `code`.
- **Project folders are scattered:** `~/Projects/*`, `~/homelab/*`, `~/METIC/*`, `~/thcon/...`.
- **Junk that floods results:**
  - **Dot-folders:** `~/.cargo/git/checkouts` and others.
  - **Python:** `venv`, `__pycache__`.
  - **Build and dependency folders:** `node_modules`, `target`, `build`, `dist`.
  - **Repository internals:** the contents of `.git`.

### Requirements
- **Speed:**
  - Results update with every keystroke without the typing ever stuttering. Target: results within
    about 100 ms.
  - The first open after login works too: if the index is still being built, show partial results
    or a short "indexing…" note.
- **Freshness:** the index rebuilds in the background on start, every N minutes (default 10), and on
  demand (a refresh key or button, and `islet find --reindex`). A file created a minute ago may be
  missing until then; that is acceptable.
- **Keyboard flow:**
  - The keybind opens the notch in Finder mode with the text field focused.
  - Up and Down move through results; Esc closes.
  - Typing starts searching immediately.
  - The bottom row shows the action keys.
- **Display:** each result shows an icon (folder or file kind), the name with matched letters
  highlighted, and its path shortened with `~`. Projects get a small "project" tag.
- **Learning:** opening a result records it (path, count, last used) in Islet's state. That record
  feeds ranking and the empty-query list.
- **CLI and IPC:** `islet find [query]` opens Finder, pre-filled when a query is given, and
  `islet find --reindex` rebuilds the index. The IPC target is `finder`.
- **Settings ("Finder" page):**
  - the keybind, with a "Set it up for me" button that asks before writing the niri config, plus
    copyable lines for other compositors;
  - search folders (default `~`) and excluded names or paths;
  - include hidden files (off by default);
  - the three apps: file manager (default: xdg default), terminal (default: detect `ghostty`, then
    `kitty`, `foot`, `alacritty`, `konsole`), editor (default: detect `code`, `codium`, `zed`);
  - the refresh interval.
- **Bar mode:** Finder works when the notch is in bar mode as well as in island mode. In bar mode the
  **text box lives in Islet's own dropdown under the DMS pill**, the same window the notch tabs
  already open in. The DMS pill stays unchanged, apart from an optional "searching" glyph sent over
  IsletLink. Keystrokes are never piped through DMS. *(Claude's call.)*

### Left to the builder
- How matching is implemented. For example, the index lives in a cache file and `fzf --filter` runs
  per query, with Islet re-ranking the top results by frecency and project boost. Or a small helper
  process; that one must be run with `python3 -I` if it is Python.
- Debouncing.
- The cache location (`~/.cache/islet/`).
- Exact scoring weights.
- How "project" is detected: the index records folders that contain `.git`.

### Non-goals
- App launching.
- Searching inside file contents.
- Listary's "quick switch" in file dialogs.
- Web search.
- A standalone repo for Finder (later).

---

## Part 2: Today (Notion ⇄ Google Calendar, shown in Islet)

### Why
The user records the school timetable and assignments in Notion, but often forgets to check them.
Notion isn't connected to Google Calendar yet. The user wants three things:
1. Notion and Google Calendar kept in sync **in both directions**.
2. Islet to show, at a glance, **today's lessons and the assignments due soon**.
3. Notion tasks usable from Islet.

### What exists
- **Dank Calendar (`dcal`, package `dankcalendar-bin` 1.6.1)** runs as a daemon and is **already
  logged in** to the user's Google (school) account. It syncs every 5 minutes and has 16 calendars:
  - several read-only Google Classroom calendars, one per subject;
  - the writable primary calendar `elang_syadewa_34rpl@student.smktelkom-mlg.sch.id`;
  - the writable Google Tasks list "Tugas Saya".

  Its IPC (`dcal ipc <method> key=value --json`) offers `events.list` (from/to RFC3339),
  `events.create`, `events.update`, `events.delete`, `calendars.list` and `tasks.*`, and
  `dcal ipc subscribe` can stream changes.

  **Use dcal for all Google access. Islet does no Google OAuth of its own.** dcal also already fires
  its own reminders for calendar events (30 minutes by default).
- **Islet's Notion integration** already exists for the Checklist. The secret is in
  `~/.config/islet/notion-token` (mode 600) and the API is called with `Notion-Version: 2022-06-28`.
  The integration must be given access to the user's "Workspace" page (Notion → ••• → Connections),
  which the setup flow explains.
- **Notion workspace "✍️ Workspace → System":**
  - **Jadwal Pelajaran** (data source `collection://d45707de-7260-4209-a7c6-51d5e73b7588`, database
    `b92a77e15b1149c8b7585d0403b858c9`) is a weekly timetable:
    - `Slot` (title);
    - `Hari` (select Senin…Sabtu);
    - `Jam` (text, format "07.00-08.30");
    - `Mapel` (relation to a subjects database);
    - `Guru` (text).
  - **Tasks** (data source `collection://deebdb7c-ac19-4e7e-990f-c6ec0b4b4eda`):
    - `Tugas` (title);
    - `Status` (status: To do, Doing, Done);
    - `Tipe` (Sekolah, CTF, Project, Personal);
    - `Prioritas` (Tinggi, Sedang, Rendah);
    - `Rencana Mulai` (date, described as "the one synced to Google Calendar");
    - `Tenggat` (date, the deadline);
    - `Mapel` and `Project` (relations);
    - `GCal ID` (text, described as "filled automatically by the sync tool, don't change"; empty today).

### Decided by the user
- **Two-way sync** between Notion and Google Calendar.
- **Morning glance:** what the user wants to see first is **today's lessons and assignments with
  close deadlines**.
- **The rest:** the user approved this design as shown in the mockup:
  - a "Hari ini" (Today) notch tab with lessons on the left (past ones dimmed, the current one marked
    "sekarang", meaning "now") and close deadlines on the right (colour by urgency, a strip for
    priority, click the circle to mark Done in Notion, and a "＋ new task" field that creates a
    Notion task);
  - the pill showing "Mapel · mulai 5 mnt lagi" ("Subject · starts in 5 min") before a lesson, and a
    due-today deadline when no music plays (a small counter when music plays);
  - the notch opening the Today tab by itself for a few seconds at the first activity of the day;
  - a single, mostly automatic "Calendar & Notion" settings page.

### Sync rules
- **Timetable → Google:**
  - Each `Jadwal Pelajaran` row becomes one **weekly recurring event** (RRULE `FREQ=WEEKLY;BYDAY=…`)
    on its weekday and time, titled with the Mapel name (or `Slot` if Mapel is empty), with Guru in
    the description.
  - **Series dates:** a series starts on that weekday in the week of the first sync (no back-filled
    history). It has no end date unless the optional "Semester ends on" setting is filled, which
    adds `UNTIL`. Holidays are not handled; skip them by deleting single occurrences in Google.
    *(Claude's call.)*
  - Changing Hari or Jam in Google (moving the **series**) writes back to the Notion row. Editing a
    single occurrence stays a Google-only exception.
  - **Deleting a row in Notion ends the series** (`UNTIL` = yesterday) instead of deleting it, so
    past lessons stay in the calendar. *(Claude's call.)*
  - **Deleting the series in Google never touches Notion.** The row is unlinked and listed in
    Settings as "Removed in Google", with two buttons: "Put it back" and "Remove from Notion"
    (which moves the page to Notion's trash). *(Claude's call, for safety.)*
  - Unparseable `Jam` values are skipped and reported in Settings, never guessed.
- **Tasks → Google:**
  - A task with `Rencana Mulai` set becomes an event at that date or time. A date without a time
    becomes all-day; a time without an end gets a default length (1 h, configurable).
  - Moving or retitling the event in Google writes back to `Rencana Mulai` or `Tugas`.
  - Status Done marks the event (a "✓ " title prefix).
  - Deleting the event in Google clears `Rencana Mulai`, but only after the event has been missing
    from **two syncs in a row** while dcal reports the account healthy (no re-auth needed, and the
    sync succeeded). A dcal hiccup or logout therefore never wipes Notion data. *(Claude's call.)*
- **`Tenggat`** is **not** made into its own event (the calendar would be cluttered); it lives in
  Islet. The GCal ID column stores the event id of the Rencana Mulai event.
- **Conflicts:** the user will edit on both sides, usually at different times; those edits must
  all sync, both ways. A conflict means **the same item changed on both sides between two syncs**,
  with different values. Then **the last edit wins, and the user is always told** (they asked for this):
  - a notification, e.g. "Tabrakan: Laporan IoT — dipakai versi Google (20.00), versi Notion (19.00)";
  - a list of recent conflicts in the Today tab header and on the settings page, each with a
    **"Pakai versi yang satunya"** ("use the other version") button that restores the losing side;
  - conflicts kept for 7 days.
  - **Detecting changes:** Islet keeps a snapshot of each linked pair (the fields it syncs, as they
    were at the last sync) and compares both sides with it.
  - **Edit times:** dcal's `events.list` returns `id, uid, recurringId, calendarId, summary,
    description, location, start, end, allDay, status, reminders, url, meetingUrl, organizer`. It
    returns **no "updated" time**, so a Google-side change is timestamped when Islet first sees it
    (at most one sync interval late). The Notion side uses `last_edited_time`.
  - **Recurrence:** dcal does support it. `events.create` and `events.update` take `recurrence` (an
    RRULE list), `events.update` takes `occurrenceStart` (moving one occurrence shifts the series by
    the start delta), and `events.list` returns `recurringId` for occurrences. The builder should
    confirm the exact JSON shapes with read-only `dcal ipc events.list --json` calls before writing
    the sync. That's allowed; any write call needs the user's confirmation as described under
    Safety.
- **Mapping:** the `GCal ID` column for Tasks. For the timetable, which has no such column, the mapping
  lives in Islet's state, or the builder adds a hidden `GCal ID` column to Jadwal Pelajaran; ask the
  user before changing the Notion schema.
- **Interval and visibility:**
  - Sync runs every few minutes (default 5, matching dcal), on demand (`islet today sync`, a
    refresh button), and shortly after a change is made from Islet.
  - The last sync time and any errors show in the Today tab header and on the settings page.
- **Target calendar:** the user's writable primary Google calendar by default; selectable in
  Settings from dcal's writable calendars.
- **Never touch Google Classroom calendars:** they're read-only and are only displayed.
- **Safety:**
  - The first sync shows a preview ("will create 32 events, change 0") that the user confirms, and
    there's a dry-run CLI.
  - Islet tags the events it creates (for example an `islet-notion:<page-id>` marker in the
    description) and only ever edits or deletes events carrying its tag.

### Today tab and pill
- **Lessons:** today's lessons come **only from the Notion timetable**, whether sync is on or off.
  Google Classroom calendars count **only as deadlines**, never as lessons. *(Claude's call: the
  Classroom calendars hold assignment due dates, and the user's real timetable is the Notion one.)*
- **Close deadlines:**
  - Notion tasks not Done, ordered by `Tenggat`, within N days (default 7). Overdue tasks are shown
    first, in red.
  - Labels: "hari ini HH.MM" (today), "besok" (tomorrow), weekday plus days left.
  - Classroom assignment events in the same window also count as deadlines, marked as coming from
    Classroom; they can't be ticked.
- **Ticking a task** sets `Status = Done` (optimistic, with rollback on error, like the existing
  Checklist).
- **Schedule clashes** (two things overlapping in time, e.g. a task's Rencana Mulai during a lesson)
  are allowed but marked with a "bentrok" ("clash") label on both items in the Today tab. No
  notification is sent; the user asked to be told about clashes, and the label does that without
  nagging. *(Claude's call on the form.)*
- **"＋ tugas baru"** creates a Notion task with `Tipe` defaulting to Sekolah, and optionally a
  Tenggat via a small date or time picker.
- **Pill priority:** an existing toast, then a lesson starting within 5 minutes, then the current
  song, then a deadline due today when idle. While music plays, a small "1 tenggat" counter.
- **Notifications:**
  - Islet does **not** duplicate dcal's event reminders.
  - It adds deadline nudges: a morning summary at the first activity of the day ("2 tenggat hari
    ini"), and one nudge 3 h before a timed deadline. Both can be turned off.
- **Morning open:** on the first user activity after 04:00 each day, the notch opens to Today for
  about 8 s (configurable, can be turned off).
- **CLI and IPC:** `islet today [sync|status|add "text"]`; IPC target `today`.

### Configuration (must be easy)
One Settings page, "Calendar & Notion", with a setup flow that **detects everything**:
- **Google:**
  - Islet shows "Connected via Dank Calendar ✓ (account …)" when dcal is running.
  - Otherwise it shows a button that runs `dcal show`, plus one sentence on how to add a Google
    account there.
- **Notion:**
  - Islet reuses the existing secret, or offers a paste field.
  - It lists the databases the integration can see and pre-selects the ones that look like a
    timetable and a task list (by their property types and names).
  - It maps columns automatically (Hari, Jam, Mapel, Guru; Tugas, Status, Rencana Mulai, Tenggat,
    Prioritas, Tipe, GCal ID) and shows the mapping with dropdowns to fix it.
  - If the Workspace page isn't shared with the integration, it gives the exact steps.
- **Toggles:**
  - sync on or off, and its direction (both ways by default);
  - target calendar;
  - deadline window in days;
  - morning open;
  - deadline nudges;
  - default event length.
- **Discoverability:** all of this is reachable through Settings search ("google", "notion",
  "jadwal", "tugas", "deadline"), and the setup guide gets an optional step for it.

### Non-goals
- Islet's own Google login.
- Syncing Google Tasks ("Tugas Saya").
- Editing Classroom items.
- A full calendar month view (dcal has one; a "Open calendar" button calls `dcal show`).

---

## Constraints that apply to both
- **Platform:** Quickshell 0.3.2 and Qt 6.12. Follow the existing style: services are `Singleton`s,
  config defaults live in `Config.defaults`, state in `Store.db`, and Settings rows use
  `win.register(key,row)` so they're searchable.
- **Performance:** Islet must stay idle at 0% CPU with nothing playing. No per-frame work for these
  features, and background processes are short-lived.
- **Secrets:** never put the Notion secret in chat, logs, the process list or URLs. Run helper Python
  with `python3 -I`.
- **Testing on the user's machine:** before changing live Islet settings during tests, save each value
  with `islet get` and restore it afterwards. Test sync against a **throwaway Notion copy or a dry run
  first**, and only touch the real calendar after the user confirms the preview.
- **Docs:** README and AGENTS.md get sections for both features. Ship with a CHANGELOG entry and a
  GitHub release, as in previous versions.

## Calls made by Claude (not explicitly asked)
- **Finder:**
  - keybind `Mod+G`;
  - refresh every 10 minutes;
  - hidden files off;
  - matching via an index plus fzf-style filtering.
- **Today:**
  - last edit wins on conflicts;
  - Tenggat isn't a calendar event;
  - single-occurrence edits stay in Google;
  - 1 h default event length;
  - morning open for 8 s after 04:00;
  - deadline nudges (morning summary and 3 h before);
  - no duplicate event reminders;
  - Classroom events counted as deadlines;
  - first-sync preview;
  - events tagged so Islet only edits its own;
  - the bar-mode text box in Islet's dropdown;
  - series start at the first sync, with no end unless a semester end date is set;
  - a Notion row deleted ends its series rather than deleting it;
  - a series deleted in Google never deletes Notion data;
  - Google-side deletions of task events only count after two healthy syncs;
  - Classroom items are deadlines only.
