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
// - A task's event that vanished clears Rencana Mulai only after two
//   syncs in a row with Dank Calendar healthy.

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
function lessonFields(l) {
    return { title: l.title, hari: l.hari, start: l.start, end: l.end };
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
        return Object.assign({ title: ev.title }, fromEvent(ev.start, ev.end));
    const done = ev.title.startsWith("✓ ");
    const title = done ? ev.title.slice(2) : ev.title;
    if (ev.allDay)
        return { title, start: localDate(new Date(ev.start)), end: "", allDay: true, done };
    return { title, start: iso(ev.start), end: iso(ev.end), allDay: false, done };
}

// ── What to send to Google ────────────────────────────────────────
function rrule(hari, semesterEnd) {
    let r = `RRULE:FREQ=WEEKLY;BYDAY=${BYDAY[hariIndex(hari)]}`;
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
        recurrence: [rrule(f.hari, opts.semesterEnd)]
    };
}

function taskEvent(t, f) {
    const title = (f.done ? "✓ " : "") + f.title;
    const description = `${TAG}${t.pageId}`;
    if (f.allDay)
        return { title, description, start: midnight(f.start).toISOString(), end: midnight(f.start, 1).toISOString(), allDay: true };
    return { title, description, start: f.start, end: f.end, allDay: false };
}

// What Notion should get from a task's Google event. A timed event of the
// default length goes back without an end, as it was written.
function notionTask(f, minutes) {
    const notionEnd = f.allDay || !f.end || new Date(f.end) - new Date(f.start) === minutes * 60000 ? "" : f.end;
    return Object.assign({}, f, { notionEnd });
}

export function plan({ lessons, tasks, events, state, now, healthy, opts }) {
    // A copy (QML's JavaScript has no structuredClone): the caller's state
    // stays as it was.
    const next = JSON.parse(JSON.stringify(state ?? emptyState()));
    next.conflicts = next.conflicts.filter(c => now.getTime() - c.at < CONFLICT_DAYS * 864e5);
    const actions = [];
    const minutes = opts.eventMinutes ?? 60;
    const byId = new Map(events.map(e => [e.id, e]));
    const tagged = new Map(events.filter(e => tagOf(e.description)).map(e => [tagOf(e.description), e]));
    const removed = new Set(next.removed.map(r => r.pageId));
    const yesterday = localDate(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1));

    const items = [];
    for (const l of lessons ?? [])
        items.push(l.error ? { pageId: l.pageId, kind: "lesson", broken: true } : { pageId: l.pageId, kind: "lesson", src: l, fields: lessonFields(l), edited: l.edited });
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

        if (!pair) {
            if (!item.fields)
                continue;
            // An event Islet made before its record was lost: take it back.
            const ev = tagged.get(item.pageId);
            if (ev) {
                pair = next.pairs[item.pageId] = { eventId: ev.id, kind: item.kind, snap: eventFields(ev, item.kind), missing: 0, notionEdited: item.edited, from: opts.seriesFrom.getTime() };
            } else {
                next.pairs[item.pageId] = { eventId: null, kind: item.kind, snap: item.fields, missing: 0, notionEdited: item.edited, from: opts.seriesFrom.getTime() };
                actions.push({ op: "createEvent", pageId: item.pageId, kind: item.kind, event: toEvent(item, null), setGcalId: item.kind === "task" });
                continue;
            }
        }

        const ev = byId.get(pair.eventId);
        if (!ev) {
            // Gone from Google — or Dank Calendar just can't see it right
            // now. Only two healthy syncs in a row count.
            if (!healthy)
                continue;
            pair.missing = (pair.missing ?? 0) + 1;
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
        actions.push(action);
        if (nChanged) {
            const conflict = { op: "conflict", pageId: item.pageId, kind: item.kind, title: n.title, used: "google", other: n, at: now.getTime() };
            actions.push(conflict);
            next.conflicts.push({ pageId: item.pageId, kind: item.kind, title: n.title, used: "google", other: n, at: now.getTime() });
        }
        pair.snap = g;
    }

    // Rows gone from Notion — only when Notion was read completely.
    if (lessons !== null && tasks !== null) {
        for (const [pageId, pair] of Object.entries(next.pairs)) {
            if (seen.has(pageId) || !pair.eventId || !byId.has(pair.eventId))
                continue;
            delete next.pairs[pageId];
            actions.push(pair.kind === "lesson" ? { op: "endSeries", eventId: pair.eventId, pageId, until: yesterday } : { op: "deleteEvent", eventId: pair.eventId, pageId });
        }
    }
    return { actions, state: next };
}
