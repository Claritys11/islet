import { test } from "node:test";
import assert from "node:assert/strict";
import { commands } from "../finder/rank.mjs";

const ids = q => commands(q).map(c => c.cmd);

test("a name or alias, from its start, finds the tab", () => {
    assert.deepEqual(ids("pomo"), ["tab:focus"]);
    assert.deepEqual(ids("Fokus"), ["tab:focus"]);
    assert.deepEqual(ids("lirik"), ["tab:media", "lyrics"]);
    assert.deepEqual(ids("ceklis"), ["tab:checklist"]);
    assert.deepEqual(ids("shelf"), ["tab:shelf"]);
    assert.deepEqual(ids("hari ini"), ["tab:today"]);
    assert.deepEqual(ids("jadwal"), ["tab:today"]);
    assert.deepEqual(ids("ini"), ["tab:today"]);
    assert.deepEqual(ids("setting"), ["settings"]);
});

test("one letter, a word's middle, or a file-ish query finds nothing", () => {
    assert.deepEqual(ids("p"), []);
    assert.deepEqual(ids("modoro"), []);
    assert.deepEqual(ids("islet"), []);
    assert.deepEqual(ids(""), []);
});

test("a command looks like a result: kind, name, a hint and an icon", () => {
    const [c] = commands("pomo");
    assert.equal(c.kind, "cmd");
    assert.equal(c.name, "Pomodoro");
    assert.equal(typeof c.short, "string");
    assert.equal(typeof c.icon, "string");
    assert.deepEqual(c.positions, []);
});
