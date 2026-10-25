import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const script = new URL("../integrations/dms/cards/place_cards.py", import.meta.url).pathname;
const ISLET = ["plugin_isletToday", "plugin_isletFocus", "plugin_isletChecklist", "plugin_isletShelf"];

function settings(data) {
    const file = join(mkdtempSync(join(tmpdir(), "cards-")), "settings.json");
    writeFileSync(file, JSON.stringify(data));
    return { file, run: mode => execFileSync("python3", ["-I", script, mode, file], { encoding: "utf8" }), read: () => JSON.parse(readFileSync(file, "utf8")) };
}
// The user's overview: rows 0–3 full on 6 columns.
const mine = [
    { id: "clock", w: 2, h: 1, col: 0, row: 0 }, { id: "weather", w: 1, h: 1, col: 2, row: 0 },
    { id: "notifications", w: 3, h: 2, col: 3, row: 0 }, { id: "calendar", w: 3, h: 3, col: 0, row: 1 },
    { id: "media", w: 3, h: 1, col: 3, row: 3 }, { id: "cpu", w: 1, h: 1, col: 3, row: 2 },
    { id: "memory", w: 1, h: 1, col: 4, row: 2 }, { id: "disk", w: 1, h: 1, col: 5, row: 2 }
];
const cells = c => { const out = []; for (let r = c.row; r < c.row + c.h; r++) for (let k = c.col; k < c.col + c.w; k++) out.push(`${r},${k}`); return out; };

test("install adds the four Islet cards in free cells, within 6 columns, overlapping nothing", () => {
    const s = settings({ dashCards: mine, dashOptions: { overview: { panelRows: 4 } }, other: 1 });
    s.run("install");
    const out = s.read();
    assert.equal(out.other, 1);
    assert.deepEqual(out.dashCards.slice(0, mine.length), mine);
    const added = out.dashCards.filter(c => ISLET.includes(c.id));
    assert.deepEqual(added.map(c => c.id).sort(), [...ISLET].sort());
    const taken = new Set();
    for (const c of out.dashCards)
        for (const x of cells(c)) {
            assert.ok(!taken.has(x), `${c.id} overlaps at ${x}`);
            taken.add(x);
            assert.ok(Number(x.split(",")[1]) < 6, `${c.id} past column 6`);
        }
    // The overview grows to show them.
    const bottom = Math.max(...out.dashCards.map(c => c.row + c.h));
    assert.equal(out.dashOptions.overview.panelRows, bottom);
});

test("install twice adds nothing more; a card you placed stays where it is", () => {
    const s = settings({ dashCards: mine.concat([{ id: "plugin_isletFocus", w: 3, h: 1, col: 0, row: 9 }]) });
    s.run("install");
    s.run("install");
    const out = s.read();
    assert.equal(out.dashCards.filter(c => c.id === "plugin_isletFocus").length, 1);
    assert.deepEqual(out.dashCards.find(c => c.id === "plugin_isletFocus"), { id: "plugin_isletFocus", w: 3, h: 1, col: 0, row: 9 });
    assert.equal(out.dashCards.filter(c => ISLET.includes(c.id)).length, 4);
});

test("uninstall takes only Islet's cards away", () => {
    const s = settings({ dashCards: mine });
    s.run("install");
    s.run("uninstall");
    assert.deepEqual(s.read().dashCards, mine);
});

test("an empty overview gets them from the top", () => {
    const s = settings({});
    s.run("install");
    const out = s.read();
    assert.equal(Math.min(...out.dashCards.map(c => c.row)), 0);
});
