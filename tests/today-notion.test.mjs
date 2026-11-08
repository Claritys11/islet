process.env.TZ = "Asia/Jakarta";
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { classify, pickDatabases, mapColumns, lessonFromRow, taskFromRow, taskPatch } from "../today/notion.mjs";

const fx = JSON.parse(readFileSync(new URL("./fixtures/notion.json", import.meta.url)));
const byId = id => fx.databases.find(d => d.id === id);

test("classify tells a timetable and a task list apart", () => {
    assert.equal(classify(byId("jadwal")).kind, "timetable");
    assert.equal(classify(byId("tasks")).kind, "tasks");
    assert.equal(classify(byId("notes")).kind, null);
    assert.equal(classify(byId("old-jadwal")).kind, null);
});

test("pickDatabases picks by shape, not just by name", () => {
    assert.deepEqual(pickDatabases(fx.databases), { timetable: "jadwal", tasks: "tasks", daily: "" });
});

test("mapColumns finds the columns", () => {
    assert.deepEqual(mapColumns("timetable", byId("jadwal").properties), { title: "Slot", hari: "Hari", jam: "Jam", mapel: "Mapel", guru: "Guru" });
    assert.deepEqual(mapColumns("tasks", byId("tasks").properties), { title: "Tugas", status: "Status", start: "Rencana Mulai", due: "Tenggat", priority: "Prioritas", type: "Tipe", gcal: "GCal ID" });
});

const lmap = { title: "Slot", hari: "Hari", jam: "Jam", mapel: "Mapel", guru: "Guru" };
const tmap = { title: "Tugas", status: "Status", start: "Rencana Mulai", due: "Tenggat", priority: "Prioritas", type: "Tipe", gcal: "GCal ID" };

test("lessonFromRow names the lesson after its subject", () => {
    assert.deepEqual(lessonFromRow(fx.rows.lesson, lmap, { m1: "Matematika" }),
        { pageId: "p1", title: "Matematika", hari: "Selasa", start: "07:00", end: "08:30", guru: "Bu Sri", edited: Date.parse("2026-10-14T14:37:00.000Z") });
    assert.equal(lessonFromRow(fx.rows.lesson, lmap, {}).title, "Selasa 1");
    assert.deepEqual(lessonFromRow(fx.rows.badLesson, lmap, {}), { error: "Jam “x” isn't a time like 07.00-08.30", pageId: "p2" });
});

test("taskFromRow reads dates with and without a time", () => {
    const t = taskFromRow(fx.rows.task, tmap);
    assert.equal(t.title, "Laporan");
    assert.equal(t.done, false);
    assert.equal(t.start, "2026-10-22");
    assert.equal(t.startHasTime, false);
    assert.equal(t.due, "2026-10-23T23:59:00.000+07:00");
    assert.equal(t.dueHasTime, true);
    assert.equal(t.priority, "Tinggi");
    assert.equal(t.gcalId, "");
    const d = taskFromRow(fx.rows.doneTask, tmap);
    assert.equal(d.done, true);
    assert.equal(d.start, "");
    assert.equal(d.gcalId, "ev-9");
});

test("taskPatch builds Notion property updates", () => {
    assert.deepEqual(taskPatch(tmap, { status: "Done" }), { Status: { status: { name: "Done" } } });
    // A Status column that's a select (as Islet's Notion template makes it).
    assert.deepEqual(taskPatch(Object.assign({}, tmap, { statusType: "select" }), { status: "Done" }), { Status: { select: { name: "Done" } } });
    assert.deepEqual(taskPatch(tmap, { gcalId: "ev-1" }), { "GCal ID": { rich_text: [{ type: "text", text: { content: "ev-1" } }] } });
    assert.deepEqual(taskPatch(tmap, { start: "2026-10-22", end: "" }), { "Rencana Mulai": { date: { start: "2026-10-22", end: null } } });
    assert.deepEqual(taskPatch(tmap, { start: "" }), { "Rencana Mulai": { date: null } });
    assert.deepEqual(taskPatch(tmap, { title: "X" }), { Tugas: { title: [{ type: "text", text: { content: "X" } }] } });
});

test("Hari is normalised, and a row without a weekday is a problem", () => {
    const row = structuredClone(fx.rows.lesson);
    row.properties.Hari.select.name = "Jum'at";
    assert.equal(lessonFromRow(row, lmap, {}).hari, "Jumat");
    row.properties.Hari.select = null;
    assert.ok(lessonFromRow(row, lmap, {}).error);
});

import { retryable } from "../today/notion.mjs";

test("retryable: what can be sent again after a dropped connection without doing it twice", () => {
    // Reads, and changes that end the same however often they're made.
    assert.equal(retryable("GET", "pages/abc"), true);
    assert.equal(retryable("POST", "search"), true);
    assert.equal(retryable("POST", "databases/abc/query"), true);
    assert.equal(retryable("PATCH", "pages/abc"), true);
    assert.equal(retryable("PATCH", "blocks/abc"), true);
    assert.equal(retryable("DELETE", "blocks/abc"), true);
    // A new page, or blocks added: twice would mean two.
    assert.equal(retryable("POST", "pages"), false);
    assert.equal(retryable("POST", "databases"), false);
    assert.equal(retryable("PATCH", "blocks/abc/children"), false);
});

import { dailyFromRow, dailyToday, dailyStale, dailyPatch, dailyNudges } from "../today/notion.mjs";
import { databaseBody } from "../today/template.mjs";

const typed = props => Object.fromEntries(Object.entries(props).map(([k, v]) => [k, Object.assign({ type: Object.keys(v)[0] }, v)]));
const dailyDb = databaseBody("daily", "home", {});
const dailyMap = mapColumns("daily", typed(dailyDb.properties));
// Saturday 31 October 2026, 10:00.
const sat = new Date(2026, 9, 31, 10, 0);
const ago = days => new Date(2026, 9, 31 - days, 9, 0).toISOString();
const dailyRow = (title, hari, jam, checked, edited, off) => ({
    id: title,
    last_edited_time: edited ?? ago(3),
    properties: {
        Tugas: { type: "title", title: [{ plain_text: title }] },
        Selesai: { type: "checkbox", checkbox: !!checked },
        Hari: { type: "multi_select", multi_select: hari.map(name => ({ name })) },
        Jam: { type: "rich_text", rich_text: jam ? [{ plain_text: jam }] : [] },
        Nonaktif: { type: "checkbox", checkbox: !!off }
    }
});

test("the Daily Tasks template is found by its shape and isn't taken for another list", () => {
    const db = { id: "d", title: [{ plain_text: "Daily Tasks" }], properties: typed(dailyDb.properties) };
    assert.equal(classify(db).kind, "daily");
    assert.equal(pickDatabases([...fx.databases, db]).daily, "d");
    assert.equal(pickDatabases([...fx.databases, db]).tasks, "tasks");
    assert.deepEqual(dailyMap, { title: "Tugas", days: "Hari", time: "Jam", done: "Selesai", off: "Nonaktif" });
});

test("another list shaped like it isn't found by itself: Islet would take its ticks off", () => {
    const db = { id: "h", title: [{ plain_text: "Habit tracker" }], properties: typed(dailyDb.properties) };
    assert.equal(classify(db).kind, null);
    assert.equal(pickDatabases([...fx.databases, db]).daily, "");
    // A tick column has to be called that, not just contain the word.
    const props = typed(dailyDb.properties);
    props["Sudah selesai dibayar"] = props.Selesai;
    delete props.Selesai;
    assert.equal(classify({ id: "x", title: [{ plain_text: "Daily Tasks" }], properties: props }).kind, null);
});

test("dailyFromRow reads the days as weekdays, tidies the time, keeps the tick", () => {
    const d = dailyFromRow(dailyRow("Olahraga", ["Senin", "Jumat", "Setiap hari"], "5:30", true, ago(1)), dailyMap);
    assert.deepEqual(d, { pageId: "Olahraga", title: "Olahraga", days: [1, 5], time: "05.30", checked: true, edited: Date.parse(ago(1)), off: false });
    assert.equal(dailyFromRow(dailyRow("x", [], "pagi"), dailyMap).time, "");
    assert.equal(dailyFromRow(dailyRow("x", [], "25.00"), dailyMap).time, "");
});

test("dailyToday: on its days only, done is a tick from today, what's left first", () => {
    const items = [
        dailyRow("Tanpa jam", [], ""),
        dailyRow("Sore", ["Sabtu"], "17.00"),
        dailyRow("Pagi", [], "05.00"),
        dailyRow("Sudah", [], "06.00", true, ago(0)),
        dailyRow("Kemarin", [], "07.00", true, ago(1)),
        dailyRow("Senin saja", ["Senin"], "07.00"),
        dailyRow("Mati", [], "", false, ago(0), true)
    ].map(r => dailyFromRow(r, dailyMap));
    const v = dailyToday(items, sat);
    assert.deepEqual(v.map(i => i.title), ["Pagi", "Kemarin", "Sore", "Tanpa jam", "Sudah"]);
    assert.deepEqual(v[0], { id: "Pagi", title: "Pagi", time: "05.00", done: false, late: true, label: "Terlambat 05.00" });
    assert.equal(v[2].late, false);
    assert.equal(v[4].done, true);
    assert.equal(v[4].late, false);
    assert.equal(dailyToday(items, sat, "en")[0].time, "05:00");
    // The next day it's back, even before the tick is taken off.
    assert.equal(dailyToday(items, new Date(2026, 10, 1, 8)).find(i => i.title === "Sudah").done, false);
});

test("dailyStale: ticks from an earlier day on any row, not today's or unticked ones", () => {
    const items = [
        dailyRow("Kemarin", [], "", true, ago(1)),
        dailyRow("Senin saja", ["Senin"], "", true, ago(5)),
        dailyRow("Mati", [], "", true, ago(2), true),
        dailyRow("Hari ini", [], "", true, ago(0)),
        dailyRow("Belum", [], "", false, ago(4))
    ].map(r => dailyFromRow(r, dailyMap));
    assert.deepEqual(dailyStale(items, sat), ["Kemarin", "Senin saja", "Mati"]);
    // Notion sends UTC: just after local midnight is still today here.
    assert.deepEqual(dailyStale([dailyFromRow(dailyRow("x", [], "", true, new Date(2026, 9, 31, 0, 30).toISOString()), dailyMap)], sat), []);
});

test("dailyPatch sets or takes off the tick", () => {
    assert.deepEqual(dailyPatch(dailyMap, true), { Selesai: { checkbox: true } });
    assert.deepEqual(dailyPatch(dailyMap, false), { Selesai: { checkbox: false } });
});

test("dailyToday: each says how it reads as a chip, in the language asked", () => {
    const items = [dailyRow("Pagi", [], "05.00"), dailyRow("Malam", [], "23.30"), dailyRow("Kapan saja", [], "")].map(r => dailyFromRow(r, dailyMap));
    const at = new Date(2026, 10, 7, 8);
    const by = lang => Object.fromEntries(dailyToday(items, at, lang).map(d => [d.title, d.label]));
    assert.deepEqual(by("id"), { Pagi: "Terlambat 05.00", Malam: "Harian 23.30", "Kapan saja": "Harian" });
    assert.deepEqual(by("en"), { Pagi: "Late 05:00", Malam: "Daily 23:30", "Kapan saja": "Daily" });
});

test("dailyNudges: once a day, in the 15 minutes before its time, not when ticked or gone by", () => {
    const at = (h, m) => new Date(2026, 10, 9, h, m);
    const d = (id, time, done = false) => ({ id, title: id, time, done });
    const list = [d("Duolingo", "19:00"), d("Baca", "19.10"), d("Tanpa jam", ""), d("Sudah", "19:00", true)];
    assert.deepEqual(dailyNudges(list, at(18, 44), {}), []);
    assert.deepEqual(dailyNudges(list, at(18, 45), {}).map(n => n.title), ["Duolingo"]);
    assert.deepEqual(dailyNudges(list, at(19, 0), {}).map(n => n.title), ["Duolingo", "Baca"]);
    assert.deepEqual(dailyNudges(list, at(19, 1), {}).map(n => n.title), ["Baca"]);
    const [first] = dailyNudges(list, at(18, 50), {});
    assert.equal(first.key, "daily:Duolingo:2026-11-09");
    assert.equal(first.time, "19:00");
    assert.deepEqual(dailyNudges(list, at(18, 51), { [first.key]: 1 }), []);
    // Tomorrow is another day's nudge.
    assert.equal(dailyNudges(list, new Date(2026, 10, 10, 18, 50), { [first.key]: 1 }).length, 1);
    assert.deepEqual(dailyNudges(undefined, at(19, 0), {}), []);
});
