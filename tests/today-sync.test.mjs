process.env.TZ = "Asia/Jakarta";
import { test } from "node:test";
import assert from "node:assert/strict";
import { plan, TAG, tagOf, emptyState } from "../today/sync.mjs";

const now = new Date("2026-10-21T10:00:00+07:00"); // Wednesday
const opts = { seriesFrom: now, semesterEnd: "", eventMinutes: 60 };
const lesson = (pageId, hari = "Selasa", start = "07:00", end = "08:30", edited = 1) => ({ pageId, title: `L-${pageId}`, hari, start, end, guru: "Bu Sri", edited });
const task = (pageId, extra = {}) => ({ pageId, title: `T-${pageId}`, status: "To do", done: false, start: "2026-10-22", startHasTime: false, end: "", due: "", dueHasTime: false, priority: "", type: "", gcalId: "", edited: 1, ...extra });
const run = (input) => plan(Object.assign({ lessons: [], tasks: [], events: [], state: emptyState(), now, healthy: true, opts }, input));
const ops = r => r.actions.map(a => a.op);

// Applies a plan's actions to fake Google and Notion sides, the way the
// service does, so a second plan can be checked for echoes.
function apply(result, { lessons = [], tasks = [], events = [] }) {
    let n = 0;
    const state = structuredClone(result.state);
    events = events.map(e => ({ ...e }));
    for (const a of result.actions) {
        if (a.op === "createEvent") {
            const id = `ev-${a.pageId}-${n++}`;
            events.push({ id, title: a.event.title, start: a.event.start, end: a.event.end, allDay: a.event.allDay, description: a.event.description, recurring: !!a.event.recurrence, rrule: a.event.recurrence?.[0] ?? "" });
            state.pairs[a.pageId].eventId = id;
            tasks = tasks.map(t => t.pageId === a.pageId ? { ...t, gcalId: id } : t);
        } else if (a.op === "updateEvent") {
            events = events.map(e => e.id === a.eventId ? { ...e, title: a.event.title, start: a.event.start, end: a.event.end, allDay: a.event.allDay, rrule: a.event.recurrence?.[0] ?? e.rrule } : e);
        } else if (a.op === "updateNotion") {
            if (a.kind === "lesson")
                lessons = lessons.map(l => l.pageId === a.pageId ? { ...l, hari: a.fields.hari, start: a.fields.start, end: a.fields.end, edited: 99 } : l);
            else
                tasks = tasks.map(t => t.pageId === a.pageId ? { ...t, title: a.fields.title, start: a.fields.start, startHasTime: !a.fields.allDay, end: a.fields.notionEnd, done: a.fields.done, edited: 99 } : t);
            state.pairs[a.pageId].notionEdited = 99;
        } else if (a.op === "setGcalId") {
            tasks = tasks.map(t => t.pageId === a.pageId ? { ...t, gcalId: a.eventId } : t);
        }
    }
    return { lessons, tasks, events, state };
}

test("tags", () => {
    assert.equal(tagOf(`Guru: X\n${TAG}abc`), "abc");
    assert.equal(tagOf("no tag"), "");
});

test("new lesson creates a weekly series from this week", () => {
    const r = run({ lessons: [lesson("p1")] });
    assert.deepEqual(ops(r), ["createEvent"]);
    const ev = r.actions[0].event;
    assert.equal(ev.title, "L-p1");
    assert.equal(new Date(ev.start).toISOString(), new Date("2026-10-20T07:00:00+07:00").toISOString());
    assert.equal(new Date(ev.end).toISOString(), new Date("2026-10-20T08:30:00+07:00").toISOString());
    assert.deepEqual(ev.recurrence, ["FREQ=WEEKLY;BYDAY=TU"]);
    assert.match(ev.description, new RegExp(`${TAG}p1$`));
    assert.equal(r.state.pairs.p1.kind, "lesson");
});

test("semester end adds UNTIL", () => {
    const r = run({ lessons: [lesson("p1")], opts: { ...opts, semesterEnd: "2026-12-19" } });
    assert.deepEqual(r.actions[0].event.recurrence, ["FREQ=WEEKLY;BYDAY=TU;UNTIL=20261219T165959Z"]);
});

test("new task with Rencana Mulai creates an all-day event and sets GCal ID", () => {
    const r = run({ tasks: [task("t1")] });
    assert.deepEqual(ops(r), ["createEvent"]);
    const a = r.actions[0];
    assert.equal(a.setGcalId, true);
    assert.equal(a.event.allDay, true);
    // Dank Calendar keeps all-day dates as midnight UTC of that date.
    assert.equal(a.event.start, "2026-10-22T00:00:00Z");
    assert.equal(a.event.end, "2026-10-23T00:00:00Z");
});

test("task without Rencana Mulai has no event", () => {
    assert.deepEqual(ops(run({ tasks: [task("t1", { start: "" })] })), []);
});

test("own writes do not echo as conflicts", () => {
    const first = run({ lessons: [lesson("p1")], tasks: [task("t1"), task("t2", { start: "2026-10-22T19:00:00.000+07:00", startHasTime: true })] });
    const sides = apply(first, { lessons: [lesson("p1")], tasks: [task("t1"), task("t2", { start: "2026-10-22T19:00:00.000+07:00", startHasTime: true })] });
    const second = run(sides);
    assert.deepEqual(second.actions, []);
});

function synced(lessons, tasks) {
    const first = run({ lessons, tasks });
    return apply(first, { lessons, tasks });
}

test("Notion change updates the event", () => {
    const s = synced([lesson("p1")], []);
    const r = run({ ...s, lessons: [lesson("p1", "Rabu", "09:00", "10:00", 50)] });
    assert.deepEqual(ops(r), ["updateEvent"]);
    assert.equal(new Date(r.actions[0].event.start).toISOString(), new Date("2026-10-21T09:00:00+07:00").toISOString());
    assert.deepEqual(r.actions[0].event.recurrence, ["FREQ=WEEKLY;BYDAY=WE"]);
});

test("Google change updates Notion", () => {
    const s = synced([lesson("p1")], []);
    s.events = s.events.map(e => ({ ...e, start: "2026-10-20T01:00:00Z", end: "2026-10-20T02:30:00Z" }));
    const r = run(s);
    assert.deepEqual(ops(r), ["updateNotion"]);
    assert.deepEqual(r.actions[0].fields, { title: "L-p1", hari: "Selasa", start: "08:00", end: "09:30", until: "" });
    assert.equal(r.actions[0].jam, "08.00-09.30");
});

test("both changed → last edit wins (Google, seen now), conflict reported", () => {
    const s = synced([], [task("t1")]);
    s.events = s.events.map(e => ({ ...e, title: "Google title" }));
    const r = run({ ...s, tasks: s.tasks.map(t => ({ ...t, title: "Notion title", edited: now.getTime() - 60000 })) });
    assert.deepEqual(ops(r), ["updateNotion", "conflict"]);
    assert.equal(r.actions[0].fields.title, "Google title");
    assert.equal(r.actions[1].used, "google");
    assert.equal(r.actions[1].other.title, "Notion title");
    assert.equal(r.state.conflicts.length, 1);
});

test("both changed the same way is not a conflict", () => {
    const s = synced([], [task("t1")]);
    s.events = s.events.map(e => ({ ...e, title: "Same" }));
    const r = run({ ...s, tasks: s.tasks.map(t => ({ ...t, title: "Same", edited: 50 })) });
    assert.deepEqual(r.actions, []);
});

test("row deleted in Notion ends the series (UNTIL yesterday)", () => {
    const s = synced([lesson("p1")], []);
    const r = run({ ...s, lessons: [] });
    assert.deepEqual(ops(r), ["endSeries"]);
    assert.equal(r.actions[0].until, "2026-10-20");
    assert.equal(r.state.pairs.p1, undefined);
});

test("unknown Notion data (a failed query) deletes nothing", () => {
    const s = synced([lesson("p1")], [task("t1")]);
    assert.deepEqual(run({ ...s, lessons: null, tasks: null }).actions, []);
});

test("series deleted in Google never touches Notion (after two healthy syncs)", () => {
    const s = synced([lesson("p1")], []);
    const once = run({ ...s, events: [] });
    assert.deepEqual(once.actions, []);
    const twice = run({ ...s, events: [], state: once.state, now: new Date(now.getTime() + 5 * 60000) });
    assert.deepEqual(ops(twice), ["removedInGoogle"]);
    assert.equal(twice.state.pairs.p1, undefined);
    assert.deepEqual(twice.state.removed.map(r => r.pageId), ["p1"]);
    // and it isn't recreated while it's listed as removed
    assert.deepEqual(run({ ...s, events: [], state: twice.state }).actions, []);
});

test("task event missing once does nothing, twice clears Rencana Mulai", () => {
    const s = synced([], [task("t1")]);
    const once = run({ ...s, events: [] });
    assert.deepEqual(once.actions, []);
    const twice = run({ ...s, events: [], state: once.state, now: new Date(now.getTime() + 5 * 60000) });
    assert.deepEqual(ops(twice), ["clearStart"]);
});

test("missing events are not deletions when dcal is unhealthy", () => {
    const s = synced([lesson("p1")], [task("t1")]);
    let st = s.state;
    for (let i = 0; i < 3; i++) {
        const r = run({ ...s, events: [], state: st, healthy: false });
        assert.deepEqual(r.actions, []);
        st = r.state;
    }
    assert.equal(st.pairs.t1.missing, 0);
});

test("untagged events are never touched", () => {
    const mine = { id: "user-ev", title: "T-t1", start: "2026-10-22", end: "2026-10-23", allDay: true, description: "my own", recurring: false };
    const r = run({ tasks: [task("t1")], events: [mine] });
    assert.deepEqual(ops(r), ["createEvent"]);
    assert.ok(!r.actions.some(a => a.eventId === "user-ev"));
});

test("a tagged event is adopted after state was lost", () => {
    const s = synced([], [task("t1")]);
    const r = run({ ...s, state: emptyState() });
    assert.deepEqual(r.actions, []);
    assert.equal(r.state.pairs.t1.eventId, s.events[0].id);
});

test("done task gets ✓ prefix; undone removes it", () => {
    const s = synced([], [task("t1")]);
    const done = run({ ...s, tasks: s.tasks.map(t => ({ ...t, done: true, edited: 50 })) });
    assert.deepEqual(ops(done), ["updateEvent"]);
    assert.equal(done.actions[0].event.title, "✓ T-t1");
    const s2 = apply(done, { ...s, tasks: s.tasks.map(t => ({ ...t, done: true, edited: 50 })) });
    const undone = run({ ...s2, tasks: s2.tasks.map(t => ({ ...t, done: false, edited: 60 })) });
    assert.equal(undone.actions[0].event.title, "T-t1");
});

test("clearing Rencana Mulai in Notion deletes Islet's event", () => {
    const s = synced([], [task("t1")]);
    const r = run({ ...s, tasks: s.tasks.map(t => ({ ...t, start: "", edited: 50 })) });
    assert.deepEqual(ops(r), ["deleteEvent"]);
    assert.equal(r.state.pairs.t1, undefined);
});

test("an all-day event reads back as its own date", () => {
    const s = synced([], [task("t1")]);
    s.events = s.events.map(e => ({ ...e, start: "2026-10-25T00:00:00Z", end: "2026-10-26T00:00:00Z" }));
    const r = run(s);
    assert.deepEqual(ops(r), ["updateNotion"]);
    assert.equal(r.actions[0].fields.start, "2026-10-25");
});

test("a timed task without an end gets the default length", () => {
    const r = run({ tasks: [task("t1", { start: "2026-10-22T19:00:00.000+07:00", startHasTime: true })] });
    const ev = r.actions[0].event;
    assert.equal(ev.allDay, false);
    assert.equal(new Date(ev.end) - new Date(ev.start), 60 * 60000);
});

test("conflicts older than 7 days are dropped", () => {
    const state = emptyState();
    state.conflicts = [{ pageId: "x", at: now.getTime() - 8 * 864e5 }, { pageId: "y", at: now.getTime() - 864e5 }];
    assert.deepEqual(run({ state }).state.conflicts.map(c => c.pageId), ["y"]);
});

test("does not change the state it was given", () => {
    const s = synced([lesson("p1")], []);
    const before = JSON.stringify(s.state);
    run({ ...s, lessons: [] });
    assert.equal(JSON.stringify(s.state), before);
});

// ── Review fixes ──────────────────────────────────────────────────
const window = { from: new Date(now.getTime() - 60 * 864e5), to: new Date(now.getTime() + 400 * 864e5) };
const full = { lesson: true, task: true };
const runW = input => run(Object.assign({ window, complete: full }, input));
const later = (state, minutes) => ({ ...state });

test("C1: a task event outside the listed window is not 'missing'", () => {
    const old = task("t1", { start: "2026-07-01" });
    const s = apply(runW({ tasks: [old] }), { tasks: [old] });
    let st = s.state;
    for (let i = 0; i < 3; i++) {
        const r = runW({ ...s, events: [], state: st, now: new Date(now.getTime() + i * 10 * 60000) });
        assert.deepEqual(r.actions, []);
        st = r.state;
    }
});

test("C2: an incomplete side never ends series or deletes events", () => {
    const s = apply(runW({ lessons: [lesson("p1")], tasks: [task("t1")] }), { lessons: [lesson("p1")], tasks: [task("t1")] });
    const r = runW({ ...s, lessons: [], tasks: [], complete: { lesson: false, task: false } });
    assert.deepEqual(r.actions, []);
    assert.ok(r.state.pairs.p1 && r.state.pairs.t1);
});

test("C2: mass removals are held back unless allowed", () => {
    const lessons = ["a", "b", "c", "d", "e"].map(id => lesson(id));
    const s = apply(runW({ lessons }), { lessons });
    const r = runW({ ...s, lessons: [] });
    assert.deepEqual(r.actions.filter(a => a.op === "endSeries"), []);
    assert.equal(r.held, 5);
    const ok = runW({ ...s, lessons: [], opts: { ...opts, allowMass: true } });
    assert.equal(ok.actions.filter(a => a.op === "endSeries").length, 5);
});

test("I1: two misses must be minutes apart", () => {
    const s = apply(runW({ tasks: [task("t1"), task("t2")] }), { tasks: [task("t1"), task("t2")] });
    const events = s.events.filter(e => !e.description.endsWith("t1"));
    const once = runW({ ...s, events });
    const soon = runW({ ...s, events, state: once.state, now: new Date(now.getTime() + 60000) });
    assert.deepEqual(soon.actions, []);
    const after = runW({ ...s, events, state: soon.state, now: new Date(now.getTime() + 6 * 60000) });
    assert.deepEqual(ops(after), ["clearStart"]);
});

test("I1: most of Islet's events vanishing at once counts as Dank Calendar not ready", () => {
    const tasks = ["a", "b", "c", "d"].map(id => task(id));
    const s = apply(runW({ tasks }), { tasks });
    let st = s.state;
    for (let i = 0; i < 3; i++) {
        const r = runW({ ...s, events: [], state: st, now: new Date(now.getTime() + i * 10 * 60000) });
        assert.deepEqual(r.actions, []);
        st = r.state;
    }
});

test("I2: Status is written only when done changed", () => {
    const s = apply(runW({ tasks: [task("t1")] }), { tasks: [task("t1")] });
    s.events = s.events.map(e => ({ ...e, title: "Renamed" }));
    const r = runW(s);
    assert.equal(r.actions[0].statusChanged, false);
    s.events = s.events.map(e => ({ ...e, title: "✓ Renamed" }));
    assert.equal(runW(s).actions[0].statusChanged, true);
});

test("endSeries on a series that hasn't started yet deletes it instead", () => {
    const fri = lesson("p1", "Jumat"); // this week's Friday is still ahead
    const s = apply(runW({ lessons: [fri] }), { lessons: [fri] });
    assert.deepEqual(ops(runW({ ...s, lessons: [] })), ["deleteEvent"]);
});

test("adopted series keep their own start", () => {
    const s = apply(runW({ lessons: [lesson("p1")] }), { lessons: [lesson("p1")] });
    const r = runW({ ...s, state: emptyState(), now: new Date(now.getTime() + 30 * 864e5), opts: { ...opts, seriesFrom: new Date(now.getTime() + 30 * 864e5) } });
    assert.equal(r.state.pairs.p1.from, new Date(s.events[0].start).getTime());
});

test("a task whose GCal ID didn't get written gets it next time", () => {
    const s = apply(runW({ tasks: [task("t1")] }), { tasks: [task("t1")] });
    const r = runW({ ...s, tasks: s.tasks.map(t => ({ ...t, gcalId: "" })) });
    assert.deepEqual(ops(r), ["setGcalId"]);
    assert.equal(r.actions[0].eventId, s.events[0].id);
});

test("a semester end set later reaches existing series", () => {
    const s = apply(runW({ lessons: [lesson("p1")] }), { lessons: [lesson("p1")] });
    s.events = s.events.map(e => ({ ...e, rrule: "RRULE:FREQ=WEEKLY;BYDAY=TU" }));
    const r = runW({ ...s, opts: { ...opts, semesterEnd: "2026-12-19" } });
    assert.deepEqual(ops(r), ["updateEvent"]);
    assert.deepEqual(r.actions[0].event.recurrence, ["FREQ=WEEKLY;BYDAY=TU;UNTIL=20261219T165959Z"]);
});
