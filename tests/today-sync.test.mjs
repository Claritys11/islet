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
            events.push({ id, title: a.event.title, start: a.event.start, end: a.event.end, allDay: a.event.allDay, description: a.event.description, recurring: !!a.event.recurrence });
            state.pairs[a.pageId].eventId = id;
            tasks = tasks.map(t => t.pageId === a.pageId ? { ...t, gcalId: id } : t);
        } else if (a.op === "updateEvent") {
            events = events.map(e => e.id === a.eventId ? { ...e, title: a.event.title, start: a.event.start, end: a.event.end, allDay: a.event.allDay } : e);
        } else if (a.op === "updateNotion") {
            if (a.kind === "lesson")
                lessons = lessons.map(l => l.pageId === a.pageId ? { ...l, hari: a.fields.hari, start: a.fields.start, end: a.fields.end, edited: 99 } : l);
            else
                tasks = tasks.map(t => t.pageId === a.pageId ? { ...t, title: a.fields.title, start: a.fields.start, startHasTime: !a.fields.allDay, end: a.fields.notionEnd, done: a.fields.done, edited: 99 } : t);
            state.pairs[a.pageId].notionEdited = 99;
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
    assert.deepEqual(ev.recurrence, ["RRULE:FREQ=WEEKLY;BYDAY=TU"]);
    assert.match(ev.description, new RegExp(`${TAG}p1$`));
    assert.equal(r.state.pairs.p1.kind, "lesson");
});

test("semester end adds UNTIL", () => {
    const r = run({ lessons: [lesson("p1")], opts: { ...opts, semesterEnd: "2026-12-19" } });
    assert.deepEqual(r.actions[0].event.recurrence, ["RRULE:FREQ=WEEKLY;BYDAY=TU;UNTIL=20261219T165959Z"]);
});

test("new task with Rencana Mulai creates an all-day event and sets GCal ID", () => {
    const r = run({ tasks: [task("t1")] });
    assert.deepEqual(ops(r), ["createEvent"]);
    const a = r.actions[0];
    assert.equal(a.setGcalId, true);
    assert.equal(a.event.allDay, true);
    assert.equal(new Date(a.event.start).toISOString(), new Date("2026-10-22T00:00:00+07:00").toISOString());
    assert.equal(new Date(a.event.end).toISOString(), new Date("2026-10-23T00:00:00+07:00").toISOString());
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
    assert.deepEqual(r.actions[0].event.recurrence, ["RRULE:FREQ=WEEKLY;BYDAY=WE"]);
});

test("Google change updates Notion", () => {
    const s = synced([lesson("p1")], []);
    s.events = s.events.map(e => ({ ...e, start: "2026-10-20T01:00:00Z", end: "2026-10-20T02:30:00Z" }));
    const r = run(s);
    assert.deepEqual(ops(r), ["updateNotion"]);
    assert.deepEqual(r.actions[0].fields, { title: "L-p1", hari: "Selasa", start: "08:00", end: "09:30" });
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
    const twice = run({ ...s, events: [], state: once.state });
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
    const twice = run({ ...s, events: [], state: once.state });
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
