import { test } from "node:test";
import assert from "node:assert/strict";
import { parseDue, dueChip, duePreview } from "../integrations/dms/desk/common/due/due.mjs";

// Friday 30 October 2026, 09:30 local.
const now = new Date(2026, 9, 30, 9, 30);
const date = text => parseDue(text, now)?.due;

test("empty or 'tanpa': no due date", () => {
    assert.deepEqual(parseDue("", now), { due: "", hasTime: false });
    assert.deepEqual(parseDue("  ", now), { due: "", hasTime: false });
    assert.deepEqual(parseDue("tanpa", now), { due: "", hasTime: false });
});

test("words: today, tomorrow, lusa, next week, in N days", () => {
    assert.equal(date("hari ini"), "2026-10-30");
    assert.equal(date("today"), "2026-10-30");
    assert.equal(date("Besok"), "2026-10-31");
    assert.equal(date("lusa"), "2026-11-01");
    assert.equal(date("minggu depan"), "2026-11-06");
    assert.equal(date("+3"), "2026-11-02");
    assert.equal(date("3 hari"), "2026-11-02");
    assert.equal(date("2 minggu"), "2026-11-13");
});

test("weekdays: the next one, a week on when it's today", () => {
    assert.equal(date("jum"), "2026-11-06");
    assert.equal(date("fri"), "2026-11-06");
    assert.equal(date("kamis"), "2026-11-05");
    assert.equal(date("thu"), "2026-11-05");
    assert.equal(date("senin"), "2026-11-02");
    assert.equal(date("minggu"), "2026-11-01");
    assert.equal(date("sabtu depan"), "2026-10-31");
});

test("dates: d/m, d-m-y, d month, month d, ISO, day of month", () => {
    assert.equal(date("5/11"), "2026-11-05");
    assert.equal(date("5-11-2027"), "2027-11-05");
    assert.equal(date("12 des"), "2026-12-12");
    assert.equal(date("12 Desember 2027"), "2027-12-12");
    assert.equal(date("nov 5"), "2026-11-05");
    assert.equal(date("2026-11-05"), "2026-11-05");
    assert.equal(date("15"), "2026-11-15");
    assert.equal(date("tgl 31"), "2026-10-31");
    // Gone by this year: next year's.
    assert.equal(date("1/1"), "2027-01-01");
    assert.equal(date("1 okt"), "2027-10-01");
});

test("a time: with a day, alone (today), am/pm", () => {
    const off = (() => {
        const o = -new Date(2026, 9, 31, 14).getTimezoneOffset();
        return `${o < 0 ? "-" : "+"}${String(Math.floor(Math.abs(o) / 60)).padStart(2, "0")}:${String(Math.abs(o) % 60).padStart(2, "0")}`;
    })();
    assert.deepEqual(parseDue("besok 14.00", now), { due: `2026-10-31T14:00:00${off}`, hasTime: true });
    assert.equal(date("besok jam 9").slice(0, 16), "2026-10-31T09:00");
    assert.equal(date("jam 23.59").slice(0, 16), "2026-10-30T23:59");
    assert.equal(date("5/11 7pm").slice(0, 16), "2026-11-05T19:00");
    assert.equal(date("14:30").slice(0, 16), "2026-10-30T14:30");
});

test("not a date: null", () => {
    assert.equal(parseDue("kapan-kapan", now), null);
    assert.equal(parseDue("31/2", now), null);
    assert.equal(parseDue("besok 25.00", now), null);
    assert.equal(parseDue("32", now), null);
});

test("dueChip: today, tomorrow, a date, late, a time", () => {
    assert.deepEqual(dueChip("", now), { text: "", late: false });
    assert.equal(dueChip("2026-10-30", now).text, "Hari ini");
    assert.equal(dueChip("2026-10-31", now, "en").text, "Tomorrow");
    assert.equal(dueChip("2026-11-06", now).text, "Jum 6 Nov");
    assert.equal(dueChip("2027-01-04", now, "en").text, "Mon 4 Jan 2027");
    assert.deepEqual(dueChip("2026-10-29", now), { text: "Terlambat", late: true });
    assert.equal(dueChip(parseDue("besok 14.00", now).due, now).text, "Besok 14.00");
});

test("duePreview: what will be saved, or that it isn't a date", () => {
    assert.equal(duePreview("", now), "");
    assert.equal(duePreview("sabtu", now), "→ Besok");
    assert.equal(duePreview("jum", now), "→ Jum 6 Nov");
    assert.equal(duePreview("jam 8", now), "→ Hari ini 08.00");
    assert.equal(duePreview("xyz", now, "en"), "date not understood");
});

import { monthGrid, monthTitle, weekHeads, picked, withDay, withTime } from "../integrations/dms/desk/common/due/due.mjs";

test("monthGrid: six weeks from the Monday on or before the 1st", () => {
    const g = monthGrid(2026, 10, now); // November 2026: the 1st is a Sunday
    assert.equal(g.length, 42);
    assert.equal(g[0].iso, "2026-10-26");
    assert.equal(g[0].inMonth, false);
    assert.equal(g[6].iso, "2026-11-01");
    assert.equal(g[6].inMonth, true);
    const oct = monthGrid(2026, 9, now);
    assert.equal(oct.find(c => c.today).iso, "2026-10-30");
    assert.equal(oct.find(c => c.iso === "2026-10-29").past, true);
    assert.equal(oct.find(c => c.iso === "2026-10-30").past, false);
});

test("monthTitle and weekHeads", () => {
    assert.equal(monthTitle(2026, 10), "November 2026");
    assert.equal(monthTitle(2026, 7, "en"), "August 2026");
    assert.deepEqual(weekHeads(), ["Sen", "Sel", "Rab", "Kam", "Jum", "Sab", "Min"]);
});

test("picked: the field's day and time for the calendar", () => {
    assert.equal(picked("", now), null);
    assert.equal(picked("xyz", now), null);
    assert.deepEqual(picked("besok", now), { iso: "2026-10-31", time: "" });
    assert.deepEqual(picked("5/11 14.30", now), { iso: "2026-11-05", time: "14.30" });
});

test("withDay and withTime: clicks become text the field can read back", () => {
    assert.equal(withDay("", "2026-11-06", now), "6/11");
    assert.equal(withDay("besok 14.00", "2026-11-06", now), "6/11 14.00");
    assert.equal(withDay("", "2027-01-04", now), "4/1/2027");
    assert.equal(withTime("6/11", "23.59", now), "6/11 23.59");
    assert.equal(withTime("6/11 23.59", "", now), "6/11");
    assert.equal(withTime("", "07.00", now), "30/10 07.00");
    for (const t of [withDay("", "2027-01-04", now), withTime("6/11", "23.59", now)])
        assert.notEqual(parseDue(t, now), null);
    assert.equal(parseDue(withDay("", "2027-01-04", now), now).due, "2027-01-04");
});
