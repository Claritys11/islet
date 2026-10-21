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
    assert.deepEqual(pickDatabases(fx.databases), { timetable: "jadwal", tasks: "tasks" });
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
    assert.deepEqual(taskPatch(tmap, { gcalId: "ev-1" }), { "GCal ID": { rich_text: [{ type: "text", text: { content: "ev-1" } }] } });
    assert.deepEqual(taskPatch(tmap, { start: "2026-10-22", end: "" }), { "Rencana Mulai": { date: { start: "2026-10-22", end: null } } });
    assert.deepEqual(taskPatch(tmap, { start: "" }), { "Rencana Mulai": { date: null } });
    assert.deepEqual(taskPatch(tmap, { title: "X" }), { Tugas: { title: [{ type: "text", text: { content: "X" } }] } });
});
