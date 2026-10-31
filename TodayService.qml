pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import "today/notion.mjs" as Notion
import "today/timetable.mjs" as Timetable
import "today/deadlines.mjs" as Deadlines
import "today/template.mjs" as Template
import "today/sync.mjs" as Sync
import "today/agenda.mjs" as Agenda

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
    // Daily tasks: a list of its own in Notion (today/notion.mjs).
    property string dailyDb: ""
    property var dailyMap: ({})
    property var daily: []
    readonly property var dailyToday: Notion.dailyToday(daily, new Date(now), Lang.code)
    property real loadedAt: 0
    // Every lesson's subject could be read (else lessons aren't synced: a
    // fallback name would rename their events).
    property bool titlesComplete: true
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
    readonly property var deadlines: Deadlines.dueSoon(tasks, classroom, new Date(now), o.todayDays, Lang.code).map(d => Object.assign(d, { clash: clashKeys.includes("task:" + d.pageId) }))
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
    // Google Calendar events around today (all calendars, Islet's copies
    // included; Agenda leaves those out).
    property var events: []
    // Today's events from calendars you write to (Classroom's read-only
    // ones are deadlines already).
    readonly property var agendaToday: Agenda.eventsOn(events, new Date(now), new Date(now), DcalService.calendars, Lang.code).filter(e => !e.readOnly)
    // Lessons and events together, by start time. `startAt` only for things
    // that begin today at a time (what "starts in N min" can be said of).
    readonly property var scheduleToday: {
        const day = new Date(now);
        const dayStart = new Date(day.getFullYear(), day.getMonth(), day.getDate()).getTime();
        const lessons = lessonsToday.map(l => Object.assign({ kind: "lesson", key: "lesson:" + l.pageId, time: Lang.id ? `${l.start.replace(":", ".")}–${l.end.replace(":", ".")}` : `${l.start}–${l.end}`, until: "", sortAt: l.startAt }, l));
        const evs = agendaToday.map(e => Object.assign({ kind: "event", sortAt: e.start.getTime(), startAt: !e.allDay && e.start.getTime() >= dayStart ? e.start.getTime() : 0, clash: false }, e));
        return lessons.concat(evs).sort((a, b) => a.sortAt - b.sortAt);
    }
    readonly property var nextLesson: scheduleToday.find(l => l.startAt && !l.past && !l.now) ?? null
    // A lesson or event starting within 5 minutes (for the pill).
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
    // Due today, or overdue Notion tasks (Classroom items can't be ticked off
    // here, so an overdue one would nag forever).
    readonly property int dueToday: deadlines.filter(d => d.urgency === "today" || (d.urgency === "overdue" && d.source === "notion")).length

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
            dailyDb = o.todayDailyDb || pick.daily;
            if (timetableDb === "" && tasksDb === "") {
                status = "setup";
                error = "Islet can't see a timetable or task list in Notion yet. Share your Workspace page with the integration (••• → Connections).";
                return;
            }
            const cols = overrides();
            const props = id => (dbs.find(d => d.id === id) ?? {}).properties ?? {};
            timetableMap = Object.assign(Notion.mapColumns("timetable", props(timetableDb)), cols.timetable ?? {});
            tasksMap = Object.assign(Notion.mapColumns("tasks", props(tasksDb)), cols.tasks ?? {});
            tasksMap.statusType = props(tasksDb)[tasksMap.status]?.type ?? "status";
            let left = 3;
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
            loadDaily(cols.daily ?? {}, done);
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
            NotionDbService.pageTitles(ids, (titles, complete) => {
                titlesComplete = complete;
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

    // A daily list that can't be read leaves the lessons and tasks working.
    function loadDaily(cols, done) {
        if (dailyDb === "") {
            daily = [];
            dailyMap = {};
            return done();
        }
        const read = properties => {
            dailyMap = Object.assign(Notion.mapColumns("daily", properties), cols);
            NotionDbService.query(dailyDb, (ok, rows) => {
                if (ok) {
                    daily = rows.map(r => Notion.dailyFromRow(r, dailyMap));
                    resetDaily();
                } else {
                    flash(rows);
                }
                done();
            });
        };
        const known = databases.find(d => d.id === dailyDb);
        if (known)
            return read(known.properties);
        // Notion's search takes a while to list a database just made.
        NotionDbService.request("GET", `databases/${dailyDb}`, null, (ok, db) => {
            if (ok)
                return read(db.properties);
            flash(db);
            done();
        });
    }

    // Ticks left from an earlier day come off, in Notion too; one that can't
    // is tried again at the next load (it doesn't count as done meanwhile).
    function resetDaily() {
        for (const id of Notion.dailyStale(daily, new Date()))
            NotionDbService.update(id, Notion.dailyPatch(dailyMap, false), ok => {
                if (ok)
                    daily = daily.map(d => d.pageId === id ? Object.assign({}, d, { checked: false, edited: Date.now() }) : d);
            });
    }

    // In Notion, at once on screen; put back if Notion refuses.
    function tickDaily(pageId, done) {
        if (!dailyMap.done)
            return flash(Lang.t("The daily list has no checkbox column (Selesai).", "Daftar harian tak punya kolom centang (Selesai)."));
        const before = daily;
        daily = daily.map(d => d.pageId === pageId ? Object.assign({}, d, { checked: done, edited: Date.now() }) : d);
        NotionDbService.update(pageId, Notion.dailyPatch(dailyMap, done), (ok, err) => {
            if (!ok) {
                daily = before;
                flash(err);
            }
        });
    }

    // Makes the Daily Tasks list next to the task list (or the timetable).
    function makeDaily(cb) {
        const finish = cb ?? (() => {});
        if (dailyDb !== "")
            return finish(true, "");
        const parent = [tasksDb, timetableDb].map(id => databases.find(d => d.id === id)?.parent?.page_id).find(id => !!id);
        if (!parent) {
            const err = Lang.t("Can't tell where to make it: share a page with Islet's integration, or pick a list in Settings.", "Tidak tahu harus dibuat di mana: bagikan satu halaman ke integrasi Islet, atau pilih daftar di Settings.");
            flash(err);
            return finish(false, err);
        }
        NotionDbService.request("POST", "databases", Template.databaseBody("daily", parent, {}), (ok, db) => {
            if (!ok) {
                flash(db);
                return finish(false, db);
            }
            Config.set("todayDailyDb", db.id, "Daily tasks list");
            finish(true, "");
            load();
        });
    }

    // ── Tasks ─────────────────────────────────────────────────────
    // A status name from the task list's own options: its first "done" (or
    // "to do") option, so it works whatever the statuses are called.
    function statusName(group) {
        const db = databases.find(d => d.id === tasksDb);
        const prop = db?.properties?.[tasksMap.status]?.status;
        const g = (prop?.groups ?? []).find(x => x.name.toLowerCase().replace(/[\s-]/g, "_") === group);
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

    // A task thrown away from the desktop To-Do: into Notion's trash (30
    // days to restore it there), off the list at once, back if Notion
    // refuses. The next sync takes its calendar event away too.
    function remove(pageId, cb) {
        const done = cb ?? (() => {});
        const before = tasks;
        if (!before.some(t => t.pageId === pageId))
            return done(false, "task not found");
        tasks = tasks.filter(t => t.pageId !== pageId);
        NotionDbService.trash(pageId, (ok, err) => {
            if (!ok) {
                tasks = before;
                flash(err);
                return done(false, err);
            }
            done(true, "");
            changed();
        });
    }

    // A new task (Tipe: Sekolah), optionally with a due date (YYYY-MM-DD).
    // `cb(ok, error)` is optional (the desktop To-Do widget waits for it).
    function add(text, due, cb) {
        text = text.trim();
        const done = cb ?? (() => {});
        if (text === "")
            return done(false, "empty task");
        if (tasksDb === "")
            return done(false, "No Notion task list set up in islet (Today).");
        const m = tasksMap;
        const props = {};
        props[m.title] = { title: [{ type: "text", text: { content: text } }] };
        if (m.type)
            props[m.type] = { select: { name: "Sekolah" } };
        // A select has no default the way Notion's status type has.
        if (m.status && m.statusType === "select")
            props[m.status] = { select: { name: statusName("to_do") } };
        if (due && m.due)
            props[m.due] = { date: { start: due } };
        NotionDbService.create(tasksDb, props, (ok, res) => {
            if (!ok) {
                flash(res);
                return done(false, res);
            }
            done(true, "");
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
            notify(Lang.t(`${n} due today`, `${n} tenggat hari ini`), deadlines.filter(x => x.urgency === "today" || x.urgency === "overdue").map(x => `${x.title} (${x.label})`).join(" · "));
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
            notify(Lang.t(`Due ${d.label}`, `Tenggat ${d.label}`), d.title);
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

    // Google events from yesterday to the deadline window's end: today's
    // agenda, and Classroom assignments (events in Google calendars Islet
    // can't write).
    function loadEvents() {
        const ro = DcalService.calendars.filter(c => c.readOnly && c.accountKind === "google" && !/holiday|libur/i.test(c.name)).map(c => c.id);
        const n = new Date();
        const from = new Date(n.getFullYear(), n.getMonth(), n.getDate() - 1);
        DcalService.listEvents(from, new Date(n.getTime() + (o.todayDays + 1) * 864e5), "", (ok, evs) => {
            if (!ok)
                return;
            events = evs;
            classroom = evs.filter(e => ro.includes(e.calendarId)).map(e => ({ id: e.id + e.start, title: e.summary, start: e.start, end: e.end, allDay: e.allDay }));
            eventsLoaded();
        });
    }
    signal eventsLoaded

    // A new event from one line ("Rapat 19.00-20.30") on `day`, in the
    // calendar Islet syncs to. cb(ok, errorText).
    function addEvent(text, day, cb) {
        const e = Agenda.parseEvent(text, day, o.todayEventMinutes, Lang.code);
        if (!e || !targetCalendar)
            return cb(false, !e ? Lang.t("Give the event a name", "Tulis nama acaranya") : Lang.t("No Google calendar Islet can write to", "Tidak ada kalender Google yang bisa ditulisi"));
        DcalService.call("events.create", { calendarId: targetCalendar, summary: e.title, start: e.start, end: e.end, allDay: e.allDay ? "true" : "false" }, (ok, r) => {
            if (ok)
                loadEvents();
            cb(ok, ok ? "" : r);
        });
    }
    Connections {
        target: DcalService
        function onRefreshed() {
            root.loadEvents();
        }
    }

    // Lessons move from "next" to "now" to "past"; deadlines get closer.
    Timer {
        running: root.o.todayEnabled
        repeat: true
        interval: 30000
        onTriggered: {
            const day = new Date(root.now).getDate();
            root.now = Date.now();
            root.checkNudges();
            // Past midnight (or back from sleep on another day): a new day's
            // daily tasks, without waiting for the next sync.
            if (new Date(root.now).getDate() !== day)
                root.load();
        }
    }
    Timer {
        running: root.o.todayEnabled
        repeat: true
        interval: Math.max(1, root.o.todaySyncMinutes) * 60000
        onTriggered: root.load()
    }
    onLoaded: {
        // Islet starting in the morning with you at the screen; otherwise
        // the first activity (the IdleMonitor) does it.
        const h = new Date().getHours();
        if (!away.isIdle && h >= 4 && h < 12)
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
    property bool _reloading: false
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

    // What isletEvents lists; events outside it don't count as missing.
    function syncWindow() {
        const n = Date.now();
        return { from: new Date(n - 60 * 864e5), to: new Date(n + 400 * 864e5) };
    }

    // Islet's events in the target calendar, one per series.
    function isletEvents(cb) {
        const w = syncWindow();
        DcalService.listEvents(w.from, w.to, Sync.TAG, (ok, evs) => {
            if (!ok)
                return cb(false, evs);
            // A series is listed once per week. It's represented by the time
            // most of its weeks have, so one week moved in Google (a single
            // exception) isn't taken for moving the whole series.
            const groups = {};
            for (const e of evs)
                if (e.calendarId === targetCalendar)
                    (groups[e.id] = groups[e.id] ?? []).push(e);
            const pickOne = list => {
                const sig = e => { const s = new Date(e.start), d = new Date(e.end); return `${s.getDay()} ${s.getHours()}:${s.getMinutes()} ${d - s}`; };
                const count = {};
                for (const e of list)
                    count[sig(e)] = (count[sig(e)] ?? 0) + 1;
                const best = Math.max(...Object.values(count));
                const usual = list.filter(e => count[sig(e)] === best);
                return usual.find(e => e.recurringId === "") ?? usual.sort((a, b) => a.start < b.start ? -1 : 1)[0];
            };
            cb(true, Object.values(groups).map(pickOne).map(e => ({ id: e.id, title: e.summary, start: e.start, end: e.end, allDay: e.allDay, description: e.description, recurring: !!e.recurrence, rrule: e.recurrence?.rrule?.[0] ?? "" })));
        });
    }

    // Many removals at once are held until allowed (Settings → Allow).
    property int held: 0
    property bool _allowMass: false

    function makePlan(cb) {
        if (targetCalendar === "")
            return cb(null, "No Google calendar to write to — is Dank Calendar signed in?");
        if (!DcalService.healthy)
            return cb(null, DcalService.error || "Dank Calendar isn't running");
        if (!notionOk)
            return cb(null, error);
        if (!titlesComplete)
            return cb(null, "Notion didn't send every subject's name; trying again next sync");
        isletEvents((ok, events) => {
            if (!ok)
                return cb(null, events);
            // A database Islet hasn't synced from before (or just switched
            // to) only adds: removals need a complete, known side.
            const dbs = syncState.dbs ?? {};
            const known = (kind, id) => id !== "" && (dbs[kind] === undefined || dbs[kind] === id);
            const result = Sync.plan({
                lessons: allLessons.concat(problems),
                tasks,
                events,
                state: syncState,
                now: new Date(),
                healthy: DcalService.healthy,
                window: syncWindow(),
                complete: { lesson: known("lesson", timetableDb), task: known("task", tasksDb) },
                opts: { seriesFrom: new Date(), semesterEnd: o.todaySemesterEnd, eventMinutes: o.todayEventMinutes, allowMass: _allowMass, lessons: o.todaySyncLessons }
            });
            _allowMass = false;
            held = result.held ?? 0;
            cb(result, "", events);
        });
    }

    // "Allow": run the held removals once.
    function allowRemovals() {
        _allowMass = true;
        sync();
    }

    function summary(actions) {
        const n = op => actions.filter(a => a.op === op).length;
        const parts = [];
        if (n("createEvent"))
            parts.push(Lang.t(`create ${n("createEvent")} events`, `buat ${n("createEvent")} event`));
        if (n("updateEvent") + n("endSeries"))
            parts.push(Lang.t(`change ${n("updateEvent") + n("endSeries")} events`, `ubah ${n("updateEvent") + n("endSeries")} event`));
        if (n("deleteEvent"))
            parts.push(Lang.t(`delete ${n("deleteEvent")} events`, `hapus ${n("deleteEvent")} event`));
        if (n("updateNotion") + n("clearStart"))
            parts.push(Lang.t(`change ${n("updateNotion") + n("clearStart")} Notion rows`, `ubah ${n("updateNotion") + n("clearStart")} baris Notion`));
        if (n("conflict"))
            parts.push(Lang.t(`${n("conflict")} clashes`, `tabrakan ${n("conflict")}`));
        if (n("removedInGoogle"))
            parts.push(Lang.t(`${n("removedInGoogle")} deleted in Google`, `dihapus di Google ${n("removedInGoogle")}`));
        return parts.length ? parts.join(" · ") : Lang.t("no changes", "tidak ada perubahan");
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
        if (!o.todayEnabled || !o.todaySync || _syncing || _reloading)
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
                lastSync = Date.now();
                if (held > 0 && syncStatus === "done") {
                    syncStatus = "held";
                    syncError = Lang.t(`${held} events would be deleted or ended at once — held. Allow it in Settings → Calendar & Notion.`, `${held} event akan dihapus/diakhiri sekaligus — ditahan. Izinkan di Settings → Calendar & Notion.`);
                }
                // What Islet wrote to Notion: read it back before the next
                // sync may run, so it isn't taken for a new change.
                _reloading = true;
                _syncing = false;
                let left = 2;
                const done = () => {
                    if (--left === 0)
                        _reloading = false;
                };
                loadTimetable(done);
                loadTasks(done);
            });
        });
    }

    // Applies the plan's actions one by one, saving as it goes (a restart
    // mid-sync keeps what was done). An action that fails is put back to how
    // it was — its record, conflict and removal entries — and the rest go
    // on; it's tried again next sync.
    function applyAll(result, events, done) {
        const before = syncState;
        const state = JSON.parse(JSON.stringify(result.state));
        state.calendar = targetCalendar;
        state.confirmed = true;
        state.dbs = { lesson: timetableDb, task: tasksDb };
        const actions = result.actions;
        const rrules = {};
        for (const e of events)
            rrules[e.id] = e.rrule;
        const errors = [];
        const undo = a => {
            if (!a.pageId)
                return;
            if (before.pairs?.[a.pageId])
                state.pairs[a.pageId] = before.pairs[a.pageId];
            else
                delete state.pairs[a.pageId];
            state.removed = state.removed.filter(r => r.pageId !== a.pageId).concat((before.removed ?? []).filter(r => r.pageId === a.pageId));
            state.conflicts = state.conflicts.filter(c => c.pageId !== a.pageId).concat((before.conflicts ?? []).filter(c => c.pageId === a.pageId));
        };
        const step = i => {
            if (i >= actions.length) {
                Store.db.todaySync = state;
                syncStatus = errors.length ? "error" : "done";
                syncError = errors.length ? Lang.t(`${errors.length} changes failed: ${errors[0]}`, `${errors.length} perubahan gagal: ${errors[0]}`) : "";
                return done();
            }
            applyOne(actions[i], state, rrules, (ok, err) => {
                if (!ok) {
                    undo(actions[i]);
                    errors.push(err);
                }
                Store.db.todaySync = JSON.parse(JSON.stringify(state));
                step(i + 1);
            });
        };
        step(0);
    }

    // The timetable's own option for a weekday ("Jum'at" if that's how
    // it's written there), so writing back adds no new option.
    function hariOption(hari) {
        const db = databases.find(d => d.id === timetableDb);
        const opts = db?.properties?.[timetableMap.hari]?.select?.options ?? [];
        const i = Timetable.hariIndex(hari);
        return (opts.find(o => Timetable.hariIndex(o.name) === i) ?? { name: hari }).name;
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
                // The event exists either way; a GCal ID that didn't get
                // written is written next sync.
                NotionDbService.update(a.pageId, Notion.taskPatch(m, { gcalId: ev.id }), () => cb(true));
            });
        case "setGcalId":
            return NotionDbService.update(a.pageId, Notion.taskPatch(m, { gcalId: a.eventId }), cb);
        case "updateEvent":
            return DcalService.call("events.update", Object.assign({ id: a.eventId }, eventParams(a.event)), cb);
        case "endSeries": {
            const rule = (rrules[a.eventId] || "").replace(/^RRULE:/, "").replace(/;UNTIL=[^;]*/, "");
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
                props[tm.hari] = { select: { name: hariOption(a.fields.hari) } };
                props[tm.jam] = { rich_text: [{ type: "text", text: { content: a.jam } }] };
                return NotionDbService.update(a.pageId, props, cb);
            }
            const f = a.fields;
            // Status only when ticked or unticked: "Doing" stays "Doing".
            const fields = { title: f.title, start: f.start, end: f.notionEnd };
            if (a.statusChanged)
                fields.status = statusName(f.done ? "complete" : "to_do");
            return NotionDbService.update(a.pageId, Notion.taskPatch(m, fields), cb);
        }
        case "clearStart":
            return NotionDbService.update(a.pageId, Notion.taskPatch(m, { start: "", gcalId: "" }), cb);
        case "conflict":
            notify(Lang.t(`Clash: ${a.title}`, `Tabrakan: ${a.title}`), Lang.t("Google Calendar's version was kept. Notion's is saved — open the Today tab to use it instead.", "Dipakai versi Google Calendar. Versi Notion disimpan — buka tab Hari ini untuk memakainya."));
            return cb(true);
        case "removedInGoogle":
            notify(Lang.t(`${a.title} was deleted in Google Calendar`, `${a.title} dihapus di Google Calendar`), Lang.t("Notion wasn't changed. Open Settings → Calendar & Notion to bring it back or delete it.", "Notion tidak diubah. Buka Settings → Calendar & Notion untuk mengembalikan atau menghapusnya."));
            return cb(true);
        }
        cb(true);
    }

    // "Pakai versi yang satunya": put the version that lost back into
    // Notion; the next sync carries it to Google.
    function useOther(index) {
        const c = conflicts[index];
        if (!c || !ready())
            return;
        const st = Object.assign({}, syncState, { conflicts: conflicts.filter((_, i) => i !== index) });
        Store.db.todaySync = st;
        const done = (ok, err) => ok ? load() : flash(err);
        if (c.kind === "lesson") {
            const props = {};
            props[timetableMap.hari] = { select: { name: hariOption(c.other.hari) } };
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
    // The sync record is only safe to change once the calendar is known (at
    // start-up a stand-in empty record would overwrite the real one).
    function ready() {
        if (targetCalendar === "" || status !== "ready" || Store.db.todaySync?.calendar !== targetCalendar) {
            flash(Lang.t("Not ready yet — try again in a moment", "Belum siap — coba lagi sebentar lagi"));
            return false;
        }
        return true;
    }

    function putBack(pageId) {
        if (!ready())
            return;
        Store.db.todaySync = Object.assign({}, syncState, { removed: removedInGoogle.filter(r => r.pageId !== pageId) });
        sync();
    }
    function removeFromNotion(pageId) {
        if (!ready())
            return;
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
        const evs = agendaToday.map(e => `event ${e.time}${e.until ? " " + e.until : ""} ${e.title} [${e.calendar}]${e.now ? " (now)" : e.past ? " (past)" : ""}`);
        const due = deadlines.map(d => `due ${d.label}: ${d.title} [${d.source}]`);
        const rest = tasks.filter(t => !t.due).map(t => `task ${t.done ? "[x]" : "[ ]"} ${t.title}`);
        const everyDay = dailyToday.map(d => `daily ${d.done ? "[x]" : "[ ]"} ${d.time ? d.time + " " : ""}${d.title}`);
        return lessons.concat(evs, due, rest, everyDay).join("\n");
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
            `daily db: ${dailyDb === "" ? "-" : dbTitle(dailyDb) || dailyDb}`,
            `lessons: ${allLessons.length}`,
            `lessons today: ${lessonsToday.length}`,
            `tasks: ${tasks.length}`,
            `daily today: ${dailyToday.filter(d => d.done).length}/${dailyToday.length}`,
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
