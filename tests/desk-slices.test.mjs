import { test } from "node:test";
import assert from "node:assert/strict";
import { splitState } from "../integrations/dms/desk/common/slices.mjs";

const base = { v: 1, hasTrack: true, title: "T", artist: "A", art: "/a.png", playing: true, line: "x", progress: 0.1,
    viz: [0.1, 0.2], timer: null, lyrics: { index: 1, lines: [{ t: 1, text: "a" }], status: "ready", synced: true },
    tasks: { status: "ready", error: "", message: "", items: [{ id: "1", title: "t" }] },
    pomodoro: { mode: "focus", clock: "25:00", running: false, progress: 0 } };

test("C1: a tick that only moves progress/viz/line changes no slice", () => {
    const a = splitState(base), b = splitState(Object.assign({}, base, { progress: 0.5, viz: [0.9, 0.1], line: "y" }));
    for (const k of ["track", "lyrics", "tasks", "pomodoro"])
        assert.equal(JSON.stringify(a[k]), JSON.stringify(b[k]), k);
});

test("C1: play/pause changes only the track slice", () => {
    const a = splitState(base), b = splitState(Object.assign({}, base, { playing: false }));
    assert.notEqual(JSON.stringify(a.track), JSON.stringify(b.track));
    assert.equal(JSON.stringify(a.tasks), JSON.stringify(b.tasks));
});

test("missing fields give null slices", () => {
    const s = splitState({ v: 1 });
    assert.equal(s.lyrics, null);
    assert.equal(s.tasks, null);
    assert.equal(s.pomodoro, null);
    assert.equal(s.track.hasTrack, false);
});

test("art: islet's file:// URL is kept as is, a bare path gets file://", () => {
    assert.equal(splitState(Object.assign({}, base, { art: "file:///c/a.img" })).track.art, "file:///c/a.img");
    assert.equal(splitState(Object.assign({}, base, { art: "/c/a.img" })).track.art, "file:///c/a.img");
    assert.equal(splitState(Object.assign({}, base, { art: "" })).track.art, "");
});

test("the DMS dashboard's parts: day, shelf and checklist pass through, null when absent", () => {
    const day = { enabled: true, schedule: [], deadlines: [] }, shelf = [{ path: "/a", name: "a" }], checklist = { source: "local", items: [] };
    const p = splitState(Object.assign({}, base, { day, shelf, checklist }));
    assert.deepEqual([p.day, p.shelf, p.checklist], [day, shelf, checklist]);
    const q = splitState(base);
    assert.deepEqual([q.day, q.shelf, q.checklist], [null, null, null]);
});
