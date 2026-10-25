import { test } from "node:test";
import assert from "node:assert/strict";
import { homePage, DATABASES, databaseBody, exampleMapel, exampleLesson, checklistPage, relationRenames } from "../today/template.mjs";
import { classify, mapColumns } from "../today/notion.mjs";
import { parseJam, hariIndex } from "../today/timetable.mjs";

const ids = { mapel: "db-mapel", jadwal: "db-jadwal", tasks: "db-tasks", notes: "db-notes" };

// What Notion gives back for a database made from a create body.
function asRead(body) {
    const properties = {};
    for (const [name, def] of Object.entries(body.properties)) {
        const type = Object.keys(def)[0];
        properties[name] = { type, [type]: def[type] };
    }
    return { title: body.title.map(t => ({ plain_text: t.text.content })), properties };
}
const body = key => databaseBody(key, "page-home", ids);

test("the home page sits in the page you chose", () => {
    const p = homePage("parent-1");
    assert.deepEqual(p.parent, { page_id: "parent-1" });
    assert.equal(p.properties.title.title[0].text.content, "Islet");
    assert.ok(p.children.length > 0);
});

test("four databases, made in an order where every relation points back", () => {
    assert.deepEqual(DATABASES, ["mapel", "jadwal", "tasks", "notes"]);
    for (const k of DATABASES) {
        const b = body(k);
        assert.deepEqual(b.parent, { type: "page_id", page_id: "page-home" });
        for (const def of Object.values(b.properties))
            if (def.relation) {
                assert.equal(def.relation.database_id, ids.mapel, k);
                assert.equal(def.relation.type, "dual_property");
            }
    }
    assert.ok(!Object.values(body("mapel").properties).some(d => d.relation));
});

test("Islet takes the timetable for a timetable, with every column found", () => {
    const db = asRead(body("jadwal"));
    assert.equal(classify(db).kind, "timetable");
    assert.deepEqual(mapColumns("timetable", db.properties), { title: "Slot", hari: "Hari", jam: "Jam", mapel: "Mapel", guru: "Guru" });
    const days = db.properties.Hari.select.options.map(o => o.name);
    assert.ok(days.every(d => hariIndex(d) >= 0) && days.length >= 5);
});

test("Islet takes Tasks for the task list, with every column found", () => {
    const db = asRead(body("tasks"));
    assert.equal(classify(db).kind, "tasks");
    assert.deepEqual(mapColumns("tasks", db.properties), { title: "Tugas", status: "Status", start: "Rencana Mulai", due: "Tenggat", priority: "Prioritas", type: "Tipe", gcal: "GCal ID" });
    assert.deepEqual(db.properties.Status.select.options.map(o => o.name), ["To do", "Doing", "Done"]);
    // New tasks from Islet are typed Sekolah.
    assert.ok(db.properties.Tipe.select.options.some(o => o.name === "Sekolah"));
    assert.match(db.properties["Sisa waktu"].formula.expression, /prop\("Tenggat"\)/);
});

test("Notes is found by its title, with the Tipe and Topik the Notes widget sorts by", () => {
    const db = asRead(body("notes"));
    assert.equal(db.title[0].plain_text, "Notes");
    assert.equal(db.properties.Tipe.type, "select");
    assert.equal(db.properties.Topik.type, "multi_select");
    assert.equal(Object.values(db.properties).filter(p => p.type === "title").length, 1);
});

test("an example lesson whose hours Islet reads, linked to an example subject", () => {
    const m = exampleMapel(ids);
    assert.deepEqual(m.parent, { database_id: ids.mapel });
    const l = exampleLesson(ids, "page-matematika");
    assert.deepEqual(l.parent, { database_id: ids.jadwal });
    assert.ok(parseJam(l.properties.Jam.rich_text[0].text.content));
    assert.equal(l.properties.Hari.select.name, "Senin");
    assert.deepEqual(l.properties.Mapel.relation, [{ id: "page-matematika" }]);
});

test("a Checklist page with to-dos for the notch's Checklist tab", () => {
    const p = checklistPage("page-home");
    assert.deepEqual(p.parent, { page_id: "page-home" });
    assert.ok(p.children.some(b => b.type === "to_do"));
});

test("the subject list's back-links get short names, once", () => {
    const props = {
        Mapel: { type: "title" },
        "Jadwal Pelajaran": { type: "relation", relation: { database_id: ids.jadwal } },
        Tasks: { type: "relation", relation: { database_id: ids.tasks } },
        Catatan: { type: "relation", relation: { database_id: ids.notes } },
    };
    assert.deepEqual(relationRenames(props, ids), { "Jadwal Pelajaran": { name: "Jadwal" }, Tasks: { name: "Tugas" } });
    assert.deepEqual(relationRenames({}, ids), {});
});
