process.env.TZ = "Asia/Jakarta";
import { test } from "node:test";
import assert from "node:assert/strict";
import { dueSoon, label, clashes } from "../today/deadlines.mjs";

const now = new Date("2026-10-21T00:30:00+07:00"); // Wednesday, just after midnight
const task = (pageId, due, extra = {}) => ({ pageId, title: pageId, done: false, due, dueHasTime: due.includes("T"), priority: "", ...extra });

test("labels", () => {
    assert.equal(label(new Date("2026-10-21T23:59:00+07:00"), true, now), "hari ini 23.59");
    assert.equal(label(new Date("2026-10-21T23:59:59+07:00"), false, now), "hari ini");
    assert.equal(label(new Date("2026-10-22T07:00:00+07:00"), true, now), "besok 07.00");
    assert.equal(label(new Date("2026-10-22T23:59:59+07:00"), false, now), "besok");
    assert.equal(label(new Date("2026-10-23T23:59:59+07:00"), false, now), "Jum, 2 hari");
    assert.equal(label(new Date("2026-10-20T23:59:59+07:00"), false, now), "terlambat 1 hari");
    assert.equal(label(new Date("2026-10-21T00:10:00+07:00"), true, now), "terlambat 20 mnt");
});

test("dueSoon: overdue first, then by date, within the window; done and undated left out", () => {
    const tasks = [
        task("later", "2026-10-23"),
        task("today", "2026-10-21"),
        task("late", "2026-10-20"),
        task("far", "2026-11-30"),
        task("done", "2026-10-21", { done: true }),
        task("nodate", ""),
    ];
    const r = dueSoon(tasks, [], now, 7);
    assert.deepEqual(r.map(d => d.key), ["notion:late", "notion:today", "notion:later"]);
    assert.deepEqual(r.map(d => d.urgency), ["overdue", "today", "later"]);
    assert.equal(r[1].label, "hari ini");
    assert.equal(r[0].source, "notion");
});

test("dueSoon counts Classroom events as deadlines", () => {
    const ev = { id: "c1", title: "Tugas IoT", start: "2026-10-22T16:59:00Z", end: "2026-10-22T16:59:00Z", allDay: false };
    const r = dueSoon([], [ev], now, 7);
    assert.equal(r.length, 1);
    assert.equal(r[0].source, "classroom");
    assert.equal(r[0].label, "besok 23.59");
});

test("clashes: overlapping items, touching ends don't count", () => {
    const at = h => new Date(`2026-10-21T${h}:00+07:00`);
    const c = clashes([
        { key: "a", start: at("08:00"), end: at("09:30") },
        { key: "b", start: at("09:00"), end: at("10:00") },
        { key: "c", start: at("10:00"), end: at("11:00") },
    ]);
    assert.deepEqual([...c].sort(), ["a", "b"]);
});

test("labels in English: 24-hour times with a colon", () => {
    assert.equal(label(new Date("2026-10-21T23:59:00+07:00"), true, now, "en"), "today 23:59");
    assert.equal(label(new Date("2026-10-21T23:59:59+07:00"), false, now, "en"), "today");
    assert.equal(label(new Date("2026-10-22T07:00:00+07:00"), true, now, "en"), "tomorrow 07:00");
    assert.equal(label(new Date("2026-10-23T23:59:59+07:00"), false, now, "en"), "Fri, 2 days");
    assert.equal(label(new Date("2026-10-20T23:59:59+07:00"), false, now, "en"), "1 day late");
    assert.equal(label(new Date("2026-10-18T23:59:59+07:00"), false, now, "en"), "3 days late");
    assert.equal(label(new Date("2026-10-21T00:10:00+07:00"), true, now, "en"), "20 min late");
    assert.equal(dueSoon([task("t", "2026-10-22")], [], now, 7, "en")[0].label, "tomorrow");
});
