pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import "today/notion.mjs" as Notion
import "today/timetable.mjs" as Timetable
import "today/deadlines.mjs" as Deadlines
import "today/sync.mjs" as Sync

// "Today": the Notion timetable and task list, today's lessons and close
// deadlines, kept in sync with Google Calendar through Dank Calendar.
Singleton {
    id: root

    readonly property var o: Config.opts

    // "loading" | "ready" | "setup" | "error"
    property string status: "loading"
    property string error: ""
    property bool notionOk: false
    // Every timetable row as a Lesson, and every task.
    property var allLessons: []
    property var tasks: []
    // Rows that couldn't be read (e.g. a Jam that isn't a time).
    property var problems: []
    property var databases: []
    property string timetableDb: ""
    property string tasksDb: ""
    property var timetableMap: ({})
    property var tasksMap: ({})
    property real loadedAt: 0
    property real now: Date.now()

    // Assignments from Google Classroom (read-only calendars), for deadlines.
    property var classroom: []

    // Today's lessons, each with: now (happening), past, clash.
    readonly property var lessonsToday: {
        const day = new Date(now);
        const at = t => {
            const [h, m] = t.split(":").map(Number);
            return new Date(day.getFullYear(), day.getMonth(), day.getDate(), h, m);
        };
        return Timetable.lessonsOn(allLessons, day).map(l => Object.assign({}, l, {
            startAt: at(l.start).getTime(),
            endAt: at(l.end).getTime(),
            now: at(l.start) <= day && day < at(l.end),
            past: at(l.end) <= day,
            clash: clashKeys.includes("lesson:" + l.pageId)
        }));
    }
    readonly property var deadlines: Deadlines.dueSoon(tasks, classroom, new Date(now), o.todayDays).map(d => Object.assign(d, { clash: clashKeys.includes("task:" + d.pageId) }))
    // Things that overlap today: lessons and timed task plans.
    readonly property var clashKeys: {
        const day = new Date(now);
        const items = Timetable.lessonsOn(allLessons, day).map(l => {
            const [h1, m1] = l.start.split(":").map(Number), [h2, m2] = l.end.split(":").map(Number);
            return { key: "lesson:" + l.pageId, start: new Date(day.getFullYear(), day.getMonth(), day.getDate(), h1, m1), end: new Date(day.getFullYear(), day.getMonth(), day.getDate(), h2, m2) };
        });
        for (const t of tasks) {
            if (t.done || !t.startHasTime)
                continue;
            const s = new Date(t.start);
            if (s.toDateString() !== day.toDateString())
                continue;
            items.push({ key: "task:" + t.pageId, start: s, end: t.end ? new Date(t.end) : new Date(s.getTime() + o.todayEventMinutes * 60000) });
        }
        return Array.from(Deadlines.clashes(items));
    }
    readonly property var nextLesson: lessonsToday.find(l => !l.past && !l.now) ?? null
    // A lesson starting within 5 minutes (for the pill).
    readonly property var soon: _fakeSoon ?? (nextLesson && nextLesson.startAt - now <= 5 * 60000 ? nextLesson : null)
    // `islet today fake-soon N`: a pretend lesson for 30 s, to see the pill.
    property var _fakeSoon: null
    function fakeSoon(minutes) {
        _fakeSoon = { title: "Contoh pelajaran", startAt: Date.now() + minutes * 60000, start: "", end: "" };
        now = Date.now();
        fakeTimer.restart();
    }
    Timer {
        id: fakeTimer
        interval: 30000
        onTriggered: root._fakeSoon = null
    }
    readonly property int dueToday: deadlines.filter(d => d.urgency === "today" || d.urgency === "overdue").length

    function dbTitle(id) {
        const db = databases.find(d => d.id.replace(/-/g, "") === id.replace(/-/g, ""));
        return db ? (db.title ?? []).map(t => t.plain_text).join("") : "";
    }

    function overrides() {
        try {
            return JSON.parse(o.todayColumns || "{}");
        } catch (e) {
            return {};
        }
    }

    function load() {
        if (!o.todayEnabled)
            return;
        if (status !== "ready")
            status = "loading";
        DcalService.refresh();
        NotionDbService.listDatabases((ok, dbs) => {
            if (!ok)
                return fail(dbs);
            databases = dbs;
            const pick = Notion.pickDatabases(dbs);
            timetableDb = o.todayTimetableDb || pick.timetable;
            tasksDb = o.todayTasksDb || pick.tasks;
            if (timetableDb === "" && tasksDb === "") {
                status = "setup";
                error = "Islet can't see a timetable or task list in Notion yet. Share your Workspace page with the integration (••• → Connections).";
                return;
            }
            const cols = overrides();
            const props = id => (dbs.find(d => d.id === id) ?? {}).properties ?? {};
            timetableMap = Object.assign(Notion.mapColumns("timetable", props(timetableDb)), cols.timetable ?? {});
            tasksMap = Object.assign(Notion.mapColumns("tasks", props(tasksDb)), cols.tasks ?? {});
            let left = 2;
            const done = () => {
                if (--left > 0)
                    return;
                notionOk = true;
                loadedAt = Date.now();
                now = Date.now();
                status = "ready";
                error = "";
                loaded();
            };
            loadTimetable(done);
            loadTasks(done);
        });
    }

    signal loaded

    function fail(message) {
        notionOk = false;
        error = message;
        status = "error";
    }

    function loadTimetable(done) {
        if (timetableDb === "") {
            allLessons = [];
            return done();
        }
        NotionDbService.query(timetableDb, (ok, rows) => {
            if (!ok)
                return fail(rows);
            const m = timetableMap;
            const ids = [];
            for (const r of rows)
                for (const rel of r.properties[m.mapel]?.relation ?? [])
                    ids.push(rel.id);
            NotionDbService.pageTitles(ids, titles => {
                const read = rows.map(r => Notion.lessonFromRow(r, m, titles));
                allLessons = read.filter(l => !l.error);
                problems = read.filter(l => l.error);
                done();
            });
        });
    }

    function loadTasks(done) {
        if (tasksDb === "") {
            tasks = [];
            return done();
        }
        NotionDbService.query(tasksDb, (ok, rows) => {
            if (!ok)
                return fail(rows);
            tasks = rows.map(r => Notion.taskFromRow(r, tasksMap));
            done();
        });
    }

    // ── Tasks ─────────────────────────────────────────────────────
    // A status name from the task list's own options: its first "done" (or
    // "to do") option, so it works whatever the statuses are called.
    function statusName(group) {
        const db = databases.find(d => d.id === tasksDb);
        const prop = db?.properties?.[tasksMap.status]?.status;
        const g = (prop?.groups ?? []).find(x => x.name.toLowerCase().replace(/ /g, "_") === group);
        const opt = (prop?.options ?? []).find(o => g?.option_ids?.includes(o.id));
        return opt?.name ?? (group === "complete" ? "Done" : "To do");
    }

    // Done in Notion, at once on screen; put back if Notion refuses.
    function tick(pageId, done) {
        const before = tasks;
        tasks = tasks.map(t => t.pageId === pageId ? Object.assign({}, t, { done, status: statusName(done ? "complete" : "to_do") }) : t);
        NotionDbService.update(pageId, Notion.taskPatch(tasksMap, { status: statusName(done ? "complete" : "to_do") }), (ok, err) => {
            if (!ok) {
                tasks = before;
                flash(err);
            } else {
                changed();
            }
        });
    }

    // A new task (Tipe: Sekolah), optionally with a due date (YYYY-MM-DD).
    function add(text, due) {
        text = text.trim();
        if (text === "" || tasksDb === "")
            return;
        const m = tasksMap;
        const props = {};
        props[m.title] = { title: [{ type: "text", text: { content: text } }] };
        if (m.type)
            props[m.type] = { select: { name: "Sekolah" } };
        if (due && m.due)
            props[m.due] = { date: { start: due } };
        NotionDbService.create(tasksDb, props, (ok, res) => {
            if (!ok)
                return flash(res);
            loadTasks(() => changed());
        });
    }

    // For tests: trash the rows tests add.
    function trashTestTasks() {
        for (const t of tasks.filter(t => t.title === "Islet test task — hapus aku"))
            NotionDbService.trash(t.pageId, () => loadTasks(() => {}));
    }

    // Something was changed from Islet: sync soon (Task 8 listens).
    signal changed

    property string message: ""
    function flash(text) {
        message = text;
        messageTimer.restart();
    }
    Timer {
        id: messageTimer
        interval: 5000
        onTriggered: root.message = ""
    }

    // ── Reminders ─────────────────────────────────────────────────
    // The notch opens to Today at the first activity of the day (after
    // 04:00), so the day's lessons and deadlines are seen without looking.
    signal morningOpen

    function today() {
        return Qt.formatDate(new Date(), "yyyy-MM-dd");
    }

    function checkMorning() {
        const d = new Date();
        if (!o.todayEnabled || d.getHours() < 4 || Store.db.todayMorning === today() || status !== "ready")
            return;
        Store.db.todayMorning = today();
        if (o.todayMorningOpen)
            morningOpen();
        const n = dueToday;
        if (o.todayNudges && n > 0)
            notify(`${n} tenggat hari ini`, deadlines.filter(x => x.urgency === "today" || x.urgency === "overdue").map(x => `${x.title} (${x.label})`).join(" · "));
    }

    IdleMonitor {
        id: away
        enabled: root.o.todayEnabled
        timeout: 60
        respectInhibitors: false
        onIsIdleChanged: if (!isIdle)
            root.checkMorning()
    }

    // One nudge 3 hours before a timed deadline.
    function checkNudges() {
        if (!o.todayNudges)
            return;
        const sent = Object.assign({}, Store.db.todayNudged ?? {});
        let changedAny = false;
        for (const d of deadlines) {
            const left = d.due - now;
            if (!d.hasTime || left <= 0 || left > 3 * 3600000 || sent[d.key])
                continue;
            sent[d.key] = now;
            changedAny = true;
            notify(`Tenggat ${d.label}`, d.title);
        }
        // Forget nudges older than two weeks.
        for (const k in sent)
            if (now - sent[k] > 14 * 864e5) {
                delete sent[k];
                changedAny = true;
            }
        if (changedAny)
            Store.db.todayNudged = sent;
    }

    function notify(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Islet", "-i", "x-office-calendar", title, body]);
    }

    // Classroom assignments: events in Google calendars Islet can't write.
    function loadClassroom() {
        const ro = DcalService.calendars.filter(c => c.readOnly && c.accountKind === "google" && !/holiday|libur/i.test(c.name)).map(c => c.id);
        if (ro.length === 0)
            return;
        const n = new Date();
        DcalService.listEvents(new Date(n.getTime() - 7 * 864e5), new Date(n.getTime() + (o.todayDays + 1) * 864e5), "", (ok, evs) => {
            if (ok)
                classroom = evs.filter(e => ro.includes(e.calendarId)).map(e => ({ id: e.id + e.start, title: e.summary, start: e.start, end: e.end, allDay: e.allDay }));
        });
    }
    Connections {
        target: DcalService
        function onRefreshed() {
            root.loadClassroom();
        }
    }

    // Lessons move from "next" to "now" to "past"; deadlines get closer.
    Timer {
        running: root.o.todayEnabled
        repeat: true
        interval: 30000
        onTriggered: {
            root.now = Date.now();
            root.checkNudges();
        }
    }
    Timer {
        running: root.o.todayEnabled
        repeat: true
        interval: Math.max(1, root.o.todaySyncMinutes) * 60000
        onTriggered: root.load()
    }
    onLoaded: {
        checkMorning();
        checkNudges();
        if (DcalService.available)
            sync();
    }

    // ── Sync with Google Calendar ─────────────────────────────────
    // "" | "syncing" | "waiting" (first sync not confirmed) | "done" | "error"
    property string syncStatus: ""
    property string syncError: ""
    property real lastSync: 0
    property bool _syncing: false
    // The first sync's plan, shown before anything is written.
    property string previewText: ""

    readonly property string targetCalendar: o.todayCalendar || (DcalService.primary?.id ?? "")
    readonly property var syncState: {
        const st = Store.db.todaySync ?? {};
        // The record belongs to one calendar; another calendar starts afresh.
        return st.calendar === targetCalendar ? st : Object.assign(Sync.emptyState(), { calendar: targetCalendar, confirmed: false });
    }
    readonly property var conflicts: syncState.conflicts ?? []
    readonly property var removedInGoogle: syncState.removed ?? []
    readonly property int linked: Object.values(syncState.pairs ?? {}).filter(p => p.eventId).length

    // Islet's events in the target calendar, one per series.
    function isletEvents(cb) {
        const n = new Date();
        DcalService.listEvents(new Date(n.getTime() - 60 * 864e5), new Date(n.getTime() + 400 * 864e5), Sync.TAG, (ok, evs) => {
            if (!ok)
                return cb(false, evs);
            const byId = {};
            for (const e of evs) {
                if (e.calendarId !== targetCalendar)
                    continue;
                const have = byId[e.id];
                // The series' own first event, or else the earliest one seen.
                if (!have || (e.recurringId === "" && have.recurringId !== "") || (have.recurringId !== "" && e.start < have.start))
                    byId[e.id] = e;
            }
            cb(true, Object.values(byId).map(e => ({ id: e.id, title: e.summary, start: e.start, end: e.end, allDay: e.allDay, description: e.description, recurring: !!e.recurrence, rrule: e.recurrence?.rrule?.[0] ?? "" })));
        });
    }

    function makePlan(cb) {
        if (!notionOk || targetCalendar === "")
            return cb(null, targetCalendar === "" ? "No Google calendar to write to — is Dank Calendar signed in?" : error);
        isletEvents((ok, events) => {
            if (!ok)
                return cb(null, events);
            const result = Sync.plan({
                lessons: allLessons.concat(problems),
                tasks,
                events,
                state: syncState,
                now: new Date(),
                healthy: DcalService.healthy,
                opts: { seriesFrom: new Date(), semesterEnd: o.todaySemesterEnd, eventMinutes: o.todayEventMinutes }
            });
            cb(result, "", events);
        });
    }

    function summary(actions) {
        const n = op => actions.filter(a => a.op === op).length;
        const parts = [];
        if (n("createEvent"))
            parts.push(`buat ${n("createEvent")} event`);
        if (n("updateEvent") + n("endSeries") + n("deleteEvent"))
            parts.push(`ubah ${n("updateEvent") + n("endSeries") + n("deleteEvent")} event`);
        if (n("updateNotion") + n("clearStart"))
            parts.push(`ubah ${n("updateNotion") + n("clearStart")} baris Notion`);
        if (n("conflict"))
            parts.push(`tabrakan ${n("conflict")}`);
        if (n("removedInGoogle"))
            parts.push(`dihapus di Google ${n("removedInGoogle")}`);
        return parts.length ? parts.join(" · ") : "tidak ada perubahan";
    }

    function preview(cb) {
        previewText = "";
        makePlan((r, err) => {
            previewText = r ? summary(r.actions) : err;
            cb?.(previewText);
        });
    }

    function confirmFirstSync() {
        Store.db.todaySync = Object.assign({}, syncState, { confirmed: true });
        sync();
    }

    function sync() {
        if (!o.todayEnabled || !o.todaySync || _syncing)
            return;
        if (!syncState.confirmed) {
            syncStatus = "waiting";
            preview();
            return;
        }
        _syncing = true;
        syncStatus = "syncing";
        makePlan((r, err, events) => {
            if (!r) {
                _syncing = false;
                syncStatus = "error";
                syncError = err;
                return;
            }
            applyAll(r, events, () => {
                _syncing = false;
                lastSync = Date.now();
                // Notion rows Islet wrote: read them again so the next plan sees them.
                loadTasks(() => {});
            });
        });
    }

    // Applies the plan's actions one by one. If one fails, the rest wait for
    // the next sync: their entries go back to what they were, so nothing is
    // half done or done twice.
    function applyAll(result, events, done) {
        const before = syncState;
        const state = JSON.parse(JSON.stringify(result.state));
        state.calendar = targetCalendar;
        state.confirmed = true;
        const actions = result.actions;
        const rrules = {};
        for (const e of events)
            rrules[e.id] = e.rrule;
        const finish = (failedAt, message) => {
            if (failedAt >= 0) {
                for (const a of actions.slice(failedAt)) {
                    if (!a.pageId)
                        continue;
                    if (before.pairs?.[a.pageId])
                        state.pairs[a.pageId] = before.pairs[a.pageId];
                    else
                        delete state.pairs[a.pageId];
                }
            }
            Store.db.todaySync = state;
            syncStatus = failedAt >= 0 ? "error" : "done";
            syncError = message ?? "";
            done();
        };
        const step = i => {
            if (i >= actions.length)
                return finish(-1);
            applyOne(actions[i], state, rrules, (ok, err) => ok ? step(i + 1) : finish(i, err));
        };
        step(0);
    }

    function eventParams(ev) {
        return { summary: ev.title, start: ev.start, end: ev.end, description: ev.description, allDay: ev.allDay ? "true" : "false", recurrence: ev.recurrence ? ev.recurrence[0] : undefined };
    }

    function untilStamp(date) {
        const [y, m, d] = date.split("-").map(Number);
        return new Date(new Date(y, m - 1, d + 1).getTime() - 1000).toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
    }

    function applyOne(a, state, rrules, cb) {
        const m = tasksMap, tm = timetableMap;
        switch (a.op) {
        case "createEvent":
            return DcalService.call("events.create", Object.assign({ calendarId: targetCalendar }, eventParams(a.event)), (ok, ev) => {
                if (!ok)
                    return cb(false, ev);
                state.pairs[a.pageId].eventId = ev.id;
                if (!a.setGcalId)
                    return cb(true);
                NotionDbService.update(a.pageId, Notion.taskPatch(m, { gcalId: ev.id }), cb);
            });
        case "updateEvent":
            return DcalService.call("events.update", Object.assign({ id: a.eventId }, eventParams(a.event)), cb);
        case "endSeries": {
            const rule = (rrules[a.eventId] || "").replace(/;UNTIL=[^;]*/, "");
            return DcalService.call("events.update", { id: a.eventId, recurrence: `${rule};UNTIL=${untilStamp(a.until)}` }, cb);
        }
        case "deleteEvent":
            return DcalService.call("events.delete", { id: a.eventId }, (ok, err) => {
                if (!ok || a.op !== "deleteEvent" || !m.gcal)
                    return cb(ok, err);
                // A task whose plan was cleared: forget its event id too.
                if (tasks.some(t => t.pageId === a.pageId))
                    NotionDbService.update(a.pageId, Notion.taskPatch(m, { gcalId: "" }), cb);
                else
                    cb(true);
            });
        case "updateNotion": {
            if (a.kind === "lesson") {
                const props = {};
                props[tm.hari] = { select: { name: a.fields.hari } };
                props[tm.jam] = { rich_text: [{ type: "text", text: { content: a.jam } }] };
                return NotionDbService.update(a.pageId, props, cb);
            }
            const f = a.fields;
            return NotionDbService.update(a.pageId, Notion.taskPatch(m, { title: f.title, start: f.start, end: f.notionEnd, status: statusName(f.done ? "complete" : "to_do") }), cb);
        }
        case "clearStart":
            return NotionDbService.update(a.pageId, Notion.taskPatch(m, { start: "", gcalId: "" }), cb);
        case "conflict":
            notify(`Tabrakan: ${a.title}`, `Dipakai versi Google Calendar. Versi Notion disimpan — buka tab Hari ini untuk memakainya.`);
            return cb(true);
        case "removedInGoogle":
            notify(`${a.title} dihapus di Google Calendar`, "Notion tidak diubah. Buka Settings → Calendar & Notion untuk mengembalikan atau menghapusnya.");
            return cb(true);
        }
        cb(true);
    }

    // "Pakai versi yang satunya": put the version that lost back into
    // Notion; the next sync carries it to Google.
    function useOther(index) {
        const c = conflicts[index];
        if (!c)
            return;
        const st = Object.assign({}, syncState, { conflicts: conflicts.filter((_, i) => i !== index) });
        Store.db.todaySync = st;
        const done = (ok, err) => ok ? load() : flash(err);
        if (c.kind === "lesson") {
            const props = {};
            props[timetableMap.hari] = { select: { name: c.other.hari } };
            props[timetableMap.jam] = { rich_text: [{ type: "text", text: { content: `${c.other.start.replace(":", ".")}-${c.other.end.replace(":", ".")}` } }] };
            NotionDbService.update(c.pageId, props, done);
        } else {
            const f = c.other;
            const plain = f.allDay || !f.end || new Date(f.end) - new Date(f.start) === o.todayEventMinutes * 60000;
            NotionDbService.update(c.pageId, Notion.taskPatch(tasksMap, { title: f.title, start: f.start, end: plain ? "" : f.end, status: statusName(f.done ? "complete" : "to_do") }), done);
        }
    }

    // A lesson whose series was deleted in Google: make it again, or remove
    // the row from Notion (to Notion's trash).
    function putBack(pageId) {
        Store.db.todaySync = Object.assign({}, syncState, { removed: removedInGoogle.filter(r => r.pageId !== pageId) });
        sync();
    }
    function removeFromNotion(pageId) {
        NotionDbService.trash(pageId, (ok, err) => {
            if (!ok)
                return flash(err);
            Store.db.todaySync = Object.assign({}, syncState, { removed: removedInGoogle.filter(r => r.pageId !== pageId) });
            load();
        });
    }

    // Changes made from Islet go out shortly after.
    Timer {
        id: soonSync
        interval: 3000
        onTriggered: root.sync()
    }
    onChanged: soonSync.restart()

    function listText() {
        const lessons = lessonsToday.map(l => `lesson ${l.start}-${l.end} ${l.title}${l.now ? " (now)" : l.past ? " (past)" : ""}${l.clash ? " [bentrok]" : ""}`);
        const due = deadlines.map(d => `due ${d.label}: ${d.title} [${d.source}]`);
        const rest = tasks.filter(t => !t.due).map(t => `task ${t.done ? "[x]" : "[ ]"} ${t.title}`);
        return lessons.concat(due, rest).join("\n");
    }

    function statusText() {
        if (status === "loading")
            return "loading";
        const d = DcalService;
        return [
            `dcal: ${!d.available ? "not running" : d.healthy ? "ok" : d.error} (${d.account || "no account"})`,
            `notion: ${notionOk ? "ok" : error}`,
            `timetable: ${dbTitle(timetableDb) || "-"}`,
            `tasks db: ${dbTitle(tasksDb) || "-"}`,
            `lessons: ${allLessons.length}`,
            `lessons today: ${lessonsToday.length}`,
            `tasks: ${tasks.length}`,
            `deadlines: ${deadlines.length}`,
            `classroom: ${classroom.length}`,
            `problems: ${problems.length}`,
            `calendar: ${(DcalService.calendars.find(c => c.id === targetCalendar) ?? {}).name ?? "-"}`,
            `linked: ${linked}`,
            `sync: ${syncStatus}${syncError ? " — " + syncError : ""}${lastSync ? " (" + Qt.formatTime(new Date(lastSync), "HH:mm") + ")" : ""}`,
            `conflicts: ${conflicts.length}`
        ].join("\n");
    }

    Component.onCompleted: Qt.callLater(load)
    // Notion's secret arrives a moment after start.
    Connections {
        target: ChecklistService
        function onTokenChanged() {
            root.load();
        }
    }
}
