// Two-way sync between Notion (the timetable and tasks) and Google Calendar
// (through Dank Calendar), as a pure function: given both sides and what
// they looked like after the last sync, it returns the actions to take and
// the state to keep. Applying the actions is the service's job.
//
// Rules (see docs/superpowers/specs/2026-10-21-finder-and-today-design.md):
// - Each side is compared with the last-synced snapshot; a change on one
//   side is copied to the other. Both changed differently → the later edit
//   wins and a conflict is reported. A Google change is only seen at sync
//   time, so its time is now.
// - Islet only ever touches events it made: their description carries
//   TAG + the Notion page id.
// - Lessons are weekly series. A row deleted in Notion ends its series; a
//   series deleted in Google never touches Notion (it's listed as removed).
// - An event only counts as gone from Google after two syncs at least a few
//   minutes apart, with Dank Calendar healthy, the event's date inside the
//   window that was listed, and most of Islet's events still there (if
//   nearly all vanish at once, Dank Calendar is still loading). Then a
//   task's Rencana Mulai is cleared; a lesson is listed as removed.
// - A side that wasn't read completely (complete.lesson / complete.task
//   false: a database missing or just switched) never ends or deletes
//   anything. Many removals at once are held back until allowed.

import { BYDAY, hariIndex, seriesStart, fromEvent } from "./timetable.mjs";

export const TAG = "islet-notion:";
const CONFLICT_DAYS = 7;

export function tagOf(description) {
    const m = String(description ?? "").match(/islet-notion:([0-9a-zA-Z-]+)/);
    return m ? m[1] : "";
}

export function emptyState() {
    return { pairs: {}, removed: [], conflicts: [] };
}

const pad = n => String(n).padStart(2, "0");
const localDate = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const iso = v => new Date(v).toISOString();
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

function midnight(dateStr, plusDays = 0) {
    const [y, m, d] = dateStr.split("-").map(Number);
    return new Date(y, m - 1, d + plusDays);
}

// ── Comparable fields ─────────────────────────────────────────────
function lessonFields(l, semesterEnd) {
    return { title: l.title, hari: l.hari, start: l.start, end: l.end, until: semesterEnd || "" };
}

// "RRULE:…;UNTIL=20261219T165959Z" → "2026-12-19" (the local date).
function untilOf(rrule) {
    const m = /UNTIL=(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z/.exec(rrule ?? "");
    return m ? localDate(new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]))) : "";
}

function taskFields(t, minutes) {
    if (!t.start)
        return null;
    const allDay = !t.startHasTime;
    const start = allDay ? t.start.slice(0, 10) : iso(t.start);
    const end = allDay ? "" : t.end ? iso(t.end) : iso(new Date(t.start).getTime() + minutes * 60000);
    return { title: t.title, start, end, allDay, done: !!t.done };
}

function eventFields(ev, kind) {
    if (kind === "lesson")
        return Object.assign({ title: ev.title }, fromEvent(ev.start, ev.end), { until: untilOf(ev.rrule) });
    const done = ev.title.startsWith("✓ ");
    const title = done ? ev.title.slice(2) : ev.title;
    // All-day dates come as midnight UTC of that date, whatever the zone.
    if (ev.allDay)
        return { title, start: String(ev.start).slice(0, 10), end: "", allDay: true, done };
    return { title, start: iso(ev.start), end: iso(ev.end), allDay: false, done };
}

// ── What to send to Google ────────────────────────────────────────
function rrule(hari, semesterEnd) {
    // Without "RRULE:": Dank Calendar adds it (Google refuses it doubled).
    let r = `FREQ=WEEKLY;BYDAY=${BYDAY[hariIndex(hari)]}`;
    // The last second of that day, local, in iCalendar's UTC form.
    if (semesterEnd)
        r += `;UNTIL=${new Date(midnight(semesterEnd, 1) - 1000).toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z")}`;
    return r;
}

function lessonEvent(l, f, from, opts) {
    const at = seriesStart(f, from);
    return {
        title: f.title,
        description: `${l.guru ? `Guru: ${l.guru}\n` : ""}${TAG}${l.pageId}`,
        start: at.start.toISOString(),
        end: at.end.toISOString(),
        allDay: false,
        recurrence: [rrule(f.hari, f.until)]
    };
}

function taskEvent(t, f) {
    const title = (f.done ? "✓ " : "") + f.title;
    const description = `${TAG}${t.pageId}`;
    // Dank Calendar keeps all-day dates as midnight UTC of the date.
    if (f.allDay)
        return { title, description, start: `${f.start}T00:00:00Z`, end: `${localDate(midnight(f.start, 1))}T00:00:00Z`, allDay: true };
    return { title, description, start: f.start, end: f.end, allDay: false };
}

// What Notion should get from a task's Google event. A timed event of the
// default length goes back without an end, as it was written.
function notionTask(f, minutes) {
    const notionEnd = f.allDay || !f.end || new Date(f.end) - new Date(f.start) === minutes * 60000 ? "" : f.end;
    return Object.assign({}, f, { notionEnd });
}

const MISS_GAP = 4 * 60000;

// Where an event sits in time, from what was last synced.
function snapDate(pair) {
    const s = pair.snap ?? {};
    if (pair.kind === "lesson")
        return null;
    return s.start ? (s.allDay ? midnight(s.start) : new Date(s.start)) : null;
}

export function plan(input) {
    const result = planOnce(input, input.opts.allowMass);
    // Many removals at once (a database moved, a cold calendar): hold them
    // back and say how many, instead of removing.
    const destructive = result.actions.filter(a => a.gone || a.op === "clearStart" || a.op === "removedInGoogle").length;
    const pairs = Object.keys(input.state?.pairs ?? {}).length;
    if (!input.opts.allowMass && destructive > Math.max(3, pairs * 0.3)) {
        const safe = planOnce(Object.assign({}, input, { healthy: false, complete: { lesson: false, task: false } }), true);
        safe.held = destructive;
        return safe;
    }
    return result;
}

function planOnce({ lessons, tasks, events, state, now, healthy, opts, window, complete }) {
    // A copy (QML's JavaScript has no structuredClone): the caller's state
    // stays as it was.
    const next = JSON.parse(JSON.stringify(state ?? emptyState()));
    next.conflicts = next.conflicts.filter(c => now.getTime() - c.at < CONFLICT_DAYS * 864e5);
    const actions = [];
    const minutes = opts.eventMinutes ?? 60;
    const win = window ?? { from: new Date(0), to: new Date(8.64e15) };
    const whole = complete ?? { lesson: lessons !== null, task: tasks !== null };
    const byId = new Map(events.map(e => [e.id, e]));
    const tagged = new Map(events.filter(e => tagOf(e.description)).map(e => [tagOf(e.description), e]));
    const removed = new Set(next.removed.map(r => r.pageId));
    const yesterday = localDate(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1));

    // Expected in the listed window: a series that hasn't ended, or a task
    // dated inside it.
    const inWindow = pair => {
        if (pair.kind === "lesson")
            return !pair.snap?.until || midnight(pair.snap.until, 1) > win.from;
        const d = snapDate(pair);
        return d !== null && d >= win.from && d <= win.to;
    };
    // Nearly all of Islet's events gone at once: Dank Calendar isn't ready.
    const expected = Object.values(next.pairs).filter(p => p.eventId && inWindow(p));
    const vanished = expected.filter(p => !byId.has(p.eventId)).length;
    const ready = healthy && !(vanished >= 3 && vanished > expected.length / 2);

    const items = [];
    for (const l of lessons ?? [])
        items.push(l.error ? { pageId: l.pageId, kind: "lesson", broken: true } : { pageId: l.pageId, kind: "lesson", src: l, fields: lessonFields(l, opts.semesterEnd), edited: l.edited });
    for (const t of tasks ?? [])
        items.push({ pageId: t.pageId, kind: "task", src: t, fields: taskFields(t, minutes), edited: t.edited });

    const toEvent = (item, pair) => item.kind === "lesson"
        ? lessonEvent(item.src, item.fields, new Date(pair?.from ?? opts.seriesFrom), opts)
        : taskEvent(item.src, item.fields);

    const seen = new Set();
    for (const item of items) {
        seen.add(item.pageId);
        if (item.broken || removed.has(item.pageId))
            continue;
        let pair = next.pairs[item.pageId];

        if (!pair || !pair.eventId) {
            if (!item.fields)
                continue;
            // An event Islet made before its record was lost: take it back.
            const ev = tagged.get(item.pageId);
            if (ev) {
                pair = next.pairs[item.pageId] = { eventId: ev.id, kind: item.kind, snap: eventFields(ev, item.kind), missing: 0, notionEdited: item.edited, from: new Date(ev.start).getTime(), first: new Date(ev.start).getTime() };
            } else {
                const event = toEvent(item, null);
                next.pairs[item.pageId] = { eventId: null, kind: item.kind, snap: item.fields, missing: 0, notionEdited: item.edited, from: opts.seriesFrom.getTime(), first: new Date(event.start).getTime() };
                actions.push({ op: "createEvent", pageId: item.pageId, kind: item.kind, event, setGcalId: item.kind === "task" });
                continue;
            }
        }

        const ev = byId.get(pair.eventId);
        if (!ev) {
            // Gone from Google — or just not listed (outside the window, or
            // Dank Calendar not ready). Only two misses minutes apart count.
            if (!ready || !inWindow(pair))
                continue;
            if (!pair.missing || now.getTime() - (pair.missedAt ?? 0) >= MISS_GAP) {
                pair.missing = (pair.missing ?? 0) + 1;
                pair.missedAt = now.getTime();
            }
            if (pair.missing < 2)
                continue;
            delete next.pairs[item.pageId];
            if (item.kind === "lesson") {
                next.removed.push({ pageId: item.pageId, title: item.src.title });
                actions.push({ op: "removedInGoogle", pageId: item.pageId, title: item.src.title });
            } else {
                actions.push({ op: "clearStart", pageId: item.pageId });
            }
            continue;
        }
        pair.missing = 0;

        // Rencana Mulai cleared in Notion: the event goes.
        if (!item.fields) {
            delete next.pairs[item.pageId];
            actions.push({ op: "deleteEvent", eventId: ev.id, pageId: item.pageId });
            continue;
        }

        // A task's GCal ID that didn't get written (or was cleared).
        if (item.kind === "task" && item.src.gcalId !== ev.id)
            actions.push({ op: "setGcalId", pageId: item.pageId, eventId: ev.id });

        const g = eventFields(ev, item.kind), n = item.fields, s = pair.snap;
        const gChanged = !same(g, s), nChanged = !same(n, s);
        if (!gChanged && !nChanged)
            continue;
        if (nChanged && (!gChanged || same(g, n))) {
            if (!same(g, n))
                actions.push({ op: "updateEvent", eventId: ev.id, pageId: item.pageId, event: toEvent(item, pair) });
            pair.snap = n;
            pair.notionEdited = item.edited;
            continue;
        }
        // Google changed (alone, or both changed differently: Google's edit
        // is seen now, so it's the later one).
        const fields = item.kind === "lesson" ? g : notionTask(g, minutes);
        const action = { op: "updateNotion", pageId: item.pageId, kind: item.kind, fields };
        if (item.kind === "lesson")
            action.jam = `${g.start.replace(":", ".")}-${g.end.replace(":", ".")}`;
        else
            action.statusChanged = g.done !== (s?.done ?? false);
        actions.push(action);
        if (nChanged) {
            actions.push({ op: "conflict", pageId: item.pageId, kind: item.kind, title: n.title, used: "google", other: n, at: now.getTime() });
            next.conflicts.push({ pageId: item.pageId, kind: item.kind, title: n.title, used: "google", other: n, at: now.getTime() });
        }
        pair.snap = g;
    }

    // Rows gone from Notion — only for a side that was read completely.
    for (const [pageId, pair] of Object.entries(next.pairs)) {
        if (seen.has(pageId) || !pair.eventId || !byId.has(pair.eventId) || !whole[pair.kind])
            continue;
        delete next.pairs[pageId];
        // A series that hasn't had its first lesson yet is simply deleted
        // (an UNTIL before its start would be refused).
        if (pair.kind === "lesson" && midnight(yesterday, 1).getTime() > (pair.first ?? pair.from))
            actions.push({ op: "endSeries", eventId: pair.eventId, pageId, until: yesterday, gone: true });
        else
            actions.push({ op: "deleteEvent", eventId: pair.eventId, pageId, gone: true });
    }
    return { actions, state: next };
}
