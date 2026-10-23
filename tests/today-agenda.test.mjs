process.env.TZ = "Asia/Jakarta";
import { test } from "node:test";
import assert from "node:assert/strict";
import { eventsOn, tasksOn, monthGrid, sameDay } from "../today/agenda.mjs";

const day = new Date(2026, 9, 23); // Friday 23 Oct 2026
const noon = new Date(2026, 9, 23, 12, 0);
const cals = [
    { id: "me", name: "me@school", color: "#9fe1e7", readOnly: false },
    { id: "class", name: "KKA X RPL 7", color: "#1967d2", readOnly: true },
];
// What dcal gives: UTC times; all-day dates at UTC midnight, end exclusive or equal.
const ev = (id, start, end, extra = {}) => ({ id, calendarId: "me", summary: id, start, end, allDay: false, description: "", ...extra });

test("an event that starts tonight and lasts two days shows today, running on", () => {
    const [e] = eventsOn([ev("trip", "2026-10-23T13:00:00Z", "2026-10-25T13:00:00Z")], day, noon, cals);
    assert.equal(e.title, "trip");
    assert.equal(e.time, "20.00 →");
    assert.equal(e.until, "s/d Min 20.00");
    assert.equal(e.color, "#9fe1e7");
    assert.equal(e.calendar, "me@school");
    assert.equal(e.now, false);
    assert.equal(e.past, false);
});

test("the same event on the middle day is all day, on its last day it ends", () => {
    const evs = [ev("trip", "2026-10-23T13:00:00Z", "2026-10-25T13:00:00Z")];
    const [mid] = eventsOn(evs, new Date(2026, 9, 24), noon, cals);
    assert.equal(mid.time, "sepanjang hari");
    assert.equal(mid.until, "s/d Min 20.00");
    const [last] = eventsOn(evs, new Date(2026, 9, 25), noon, cals);
    assert.equal(last.time, "→ 20.00");
    assert.equal(last.until, "");
});

test("a plain event: its times, and whether it is now or past", () => {
    const evs = [ev("a", "2026-10-23T04:30:00Z", "2026-10-23T06:00:00Z"), ev("b", "2026-10-23T01:00:00Z", "2026-10-23T02:00:00Z")];
    const r = eventsOn(evs, day, noon, cals);
    assert.deepEqual(r.map(e => [e.title, e.time, e.now, e.past]), [["b", "08.00–09.00", false, true], ["a", "11.30–13.00", true, false]]);
});

test("all-day events: by their date, first, and the end date is not a day of it", () => {
    const evs = [
        ev("timed", "2026-10-23T01:00:00Z", "2026-10-23T02:00:00Z"),
        ev("holiday", "2026-10-23T00:00:00Z", "2026-10-24T00:00:00Z", { allDay: true }),
        ev("zero", "2026-10-23T00:00:00Z", "2026-10-23T00:00:00Z", { allDay: true }),
        ev("camp", "2026-10-21T00:00:00Z", "2026-10-24T00:00:00Z", { allDay: true }),
        ev("yesterday", "2026-10-22T00:00:00Z", "2026-10-23T00:00:00Z", { allDay: true }),
    ];
    const r = eventsOn(evs, day, noon, cals);
    assert.deepEqual(r.map(e => e.title), ["camp", "holiday", "zero", "timed"]);
    assert.deepEqual(r.slice(0, 3).map(e => [e.time, e.until]), [["sepanjang hari", ""], ["sepanjang hari", ""], ["sepanjang hari", ""]]);
    const [camp] = eventsOn(evs, new Date(2026, 9, 21), noon, cals);
    assert.equal(camp.until, "s/d Jum");
});

test("Islet's own copies of Notion items are left out; read-only calendars are marked", () => {
    const evs = [
        ev("copy", "2026-10-23T01:00:00Z", "2026-10-23T02:00:00Z", { description: "islet-notion:abc" }),
        ev("assignment", "2026-10-23T14:59:00Z", "2026-10-23T15:00:00Z", { calendarId: "class" }),
    ];
    const r = eventsOn(evs, day, noon, cals);
    assert.deepEqual(r.map(e => [e.title, e.readOnly]), [["assignment", true]]);
});

test("an event listed twice (two calendars' views) shows once; unknown calendar is fine", () => {
    const e = ev("x", "2026-10-23T01:00:00Z", "2026-10-23T02:00:00Z", { calendarId: "gone" });
    const r = eventsOn([e, { ...e }], day, noon, cals);
    assert.equal(r.length, 1);
    assert.equal(r[0].calendar, "");
    assert.equal(typeof r[0].color, "string");
});

test("an untitled event gets a name", () => {
    const [e] = eventsOn([ev("", "2026-10-23T01:00:00Z", "2026-10-23T02:00:00Z")], day, noon, cals);
    assert.equal(e.title, "(tanpa judul)");
});

test("tasksOn: unfinished Notion tasks due that day", () => {
    const tasks = [
        { pageId: "a", title: "Essay", done: false, due: "2026-10-23", dueHasTime: false, priority: "Tinggi" },
        { pageId: "b", title: "Quiz", done: false, due: "2026-10-23T09:00:00+07:00", dueHasTime: true, priority: "" },
        { pageId: "c", title: "Done", done: true, due: "2026-10-23", dueHasTime: false },
        { pageId: "d", title: "Other day", done: false, due: "2026-10-24", dueHasTime: false },
        { pageId: "e", title: "No date", done: false, due: "", dueHasTime: false },
    ];
    assert.deepEqual(tasksOn(tasks, day).map(t => [t.title, t.time, t.priority]), [["Quiz", "09.00", ""], ["Essay", "tenggat", "Tinggi"]]);
});

test("monthGrid: six Monday-first weeks around the month", () => {
    const g = monthGrid(2026, 9);
    assert.equal(g.length, 42);
    assert.ok(sameDay(g[0], new Date(2026, 8, 28)));
    assert.equal(g[0].getDay(), 1);
    assert.ok(sameDay(g[3], new Date(2026, 9, 1)));
    assert.ok(sameDay(g[41], new Date(2026, 10, 8)));
    // A month starting on Monday starts the grid itself.
    assert.ok(sameDay(monthGrid(2026, 5)[0], new Date(2026, 5, 1)));
    // Months roll over the year.
    assert.ok(sameDay(monthGrid(2026, 12)[0], new Date(2026, 11, 28)));
});
