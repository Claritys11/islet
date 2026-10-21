// Dates here are the user's: Asia/Jakarta (UTC+7, no daylight saving).
process.env.TZ = "Asia/Jakarta";
import { test } from "node:test";
import assert from "node:assert/strict";
import { parseJam, hariIndex, HARI, BYDAY, lessonsOn, seriesStart, fromEvent } from "../today/timetable.mjs";

test("runs in Jakarta time", () => assert.equal(new Date("2026-10-20T00:00:00Z").getHours(), 7));

test("parseJam reads the usual ways of writing a time range", () => {
    for (const s of ["07.00-08.30", "07:00 - 08:30", "7.00–8.30", "0700-0830", " 07.00 -08.30 "])
        assert.deepEqual(parseJam(s), { start: "07:00", end: "08:30" }, s);
    assert.equal(parseJam("08.30-07.00"), null);
    assert.equal(parseJam("x"), null);
    assert.equal(parseJam("25.00-26.00"), null);
});

test("hariIndex", () => {
    assert.equal(hariIndex("Kamis"), 4);
    assert.equal(hariIndex("jum'at"), 5);
    assert.equal(hariIndex("Jumat"), 5);
    assert.equal(hariIndex("Libur"), -1);
    assert.equal(HARI[2], "Selasa");
    assert.equal(BYDAY[2], "TU");
});

const lessons = [
    { pageId: "b", title: "B", hari: "Selasa", start: "10:15", end: "11:45", guru: "" },
    { pageId: "a", title: "A", hari: "Selasa", start: "07:00", end: "08:30", guru: "" },
    { pageId: "c", title: "C", hari: "Rabu", start: "07:00", end: "08:30", guru: "" },
];

test("lessonsOn gives that weekday's lessons in order, by local date", () => {
    const tuesdayJustAfterMidnight = new Date("2026-10-20T00:30:00+07:00");
    assert.deepEqual(lessonsOn(lessons, tuesdayJustAfterMidnight).map(l => l.pageId), ["a", "b"]);
});

test("seriesStart begins in the week of the first sync", () => {
    const wed = new Date("2026-10-21T10:00:00+07:00");
    const senin = seriesStart({ hari: "Senin", start: "07:00", end: "08:30" }, wed);
    assert.equal(senin.start.toISOString(), new Date("2026-10-19T07:00:00+07:00").toISOString());
    assert.equal(senin.end.toISOString(), new Date("2026-10-19T08:30:00+07:00").toISOString());
    const jumat = seriesStart({ hari: "Jumat", start: "13:00", end: "14:00" }, wed);
    assert.equal(jumat.start.toISOString(), new Date("2026-10-23T13:00:00+07:00").toISOString());
});

test("fromEvent reads an event back as weekday and times", () => {
    assert.deepEqual(fromEvent("2026-10-20T01:00:00Z", "2026-10-20T02:30:00Z"), { hari: "Selasa", start: "08:00", end: "09:30" });
});
