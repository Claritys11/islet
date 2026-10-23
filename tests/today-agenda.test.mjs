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

import { parseEvent } from "../today/agenda.mjs";

test("parseEvent: a title with a time range", () => {
    const e = parseEvent("Rapat OSIS 19.00-20.30", day, 60);
    assert.equal(e.title, "Rapat OSIS");
    assert.equal(e.allDay, false);
    assert.equal(e.start, new Date(2026, 9, 23, 19, 0).toISOString());
    assert.equal(e.end, new Date(2026, 9, 23, 20, 30).toISOString());
    assert.equal(e.label, "Jum 23 Okt · 19.00–20.30");
});

test("parseEvent: other ways to write times", () => {
    const at = (text, h1, m1, h2, m2) => {
        const e = parseEvent(text, day, 60);
        assert.deepEqual([e.title, e.start, e.end], [e.title, new Date(2026, 9, 23, h1, m1).toISOString(), new Date(2026, 9, 23, h2, m2).toISOString()], text);
        return e.title;
    };
    assert.equal(at("Les gitar jam 16", 16, 0, 17, 0), "Les gitar");
    assert.equal(at("pukul 7.30 Upacara", 7, 30, 8, 30), "Upacara");
    assert.equal(at("Futsal 15:00 – 17:00", 15, 0, 17, 0), "Futsal");
    assert.equal(at("Belajar 13.00 sampai 14.15", 13, 0, 14, 15), "Belajar");
    assert.equal(at("Nonton 20.00 s/d 22.00", 20, 0, 22, 0), "Nonton");
});

test("parseEvent: no end takes the default length; an end before the start is the next day", () => {
    const e = parseEvent("Main 19.00", day, 90);
    assert.equal(e.end, new Date(2026, 9, 23, 20, 30).toISOString());
    const late = parseEvent("Ronda 22.00-01.00", day, 60);
    assert.equal(late.end, new Date(2026, 9, 24, 1, 0).toISOString());
    assert.equal(late.label, "Jum 23 Okt · 22.00–01.00");
});

test("parseEvent: no time is an all-day event, sent as dcal wants dates", () => {
    const e = parseEvent("  Hari Guru  ", day, 60);
    assert.equal(e.title, "Hari Guru");
    assert.equal(e.allDay, true);
    assert.equal(e.start, "2026-10-23T00:00:00Z");
    assert.equal(e.end, "2026-10-24T00:00:00Z");
    assert.equal(e.label, "Jum 23 Okt · sepanjang hari");
    // Month and year ends roll over.
    assert.equal(parseEvent("Tahun baru", new Date(2026, 11, 31), 60).end, "2027-01-01T00:00:00Z");
});

test("parseEvent: nothing to call it, or only a time, is not an event; a bad hour is just words", () => {
    assert.equal(parseEvent("", day, 60), null);
    assert.equal(parseEvent("   ", day, 60), null);
    assert.equal(parseEvent("19.00-20.00", day, 60), null);
    const e = parseEvent("Kelas 10.12 bahas 25.99", day, 60);
    assert.equal(e.title, "Kelas bahas 25.99");
    assert.equal(e.start, new Date(2026, 9, 23, 10, 12).toISOString());
});
