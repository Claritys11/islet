import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const script = new URL("../integrations/dms/desk/place.py", import.meta.url).pathname;

function files(settings, session) {
    const dir = mkdtempSync(join(tmpdir(), "place-"));
    const a = join(dir, "settings.json"), b = join(dir, "session.json");
    if (settings !== undefined)
        writeFileSync(a, JSON.stringify(settings));
    if (session !== undefined)
        writeFileSync(b, JSON.stringify(session));
    const run = (mode, side) => execFileSync("python3", ["-I", script, mode, a, b].concat(side ? [side] : []), { encoding: "utf8" });
    const read = () => [JSON.parse(readFileSync(a, "utf8")), existsSync(b) ? JSON.parse(readFileSync(b, "utf8")) : null];
    return { run, read };
}

const ours = s => (s.desktopWidgetInstances ?? []).filter(i => i.widgetType.startsWith("deskw"));

test("install puts six widgets on the desktop, each with a place of its own", () => {
    const f = files({ theme: "dark", desktopWidgetInstances: [{ id: "dw_1", widgetType: "systemMonitor", enabled: true, config: {} }] }, { other: 1 });
    f.run("install");
    const [s, sess] = f.read();
    assert.equal(s.theme, "dark");
    assert.equal(s.desktopWidgetInstances[0].id, "dw_1");
    const w = ours(s);
    assert.deepEqual(w.map(i => i.widgetType).sort(), ["deskwCalendar", "deskwClock", "deskwLyrics", "deskwNotes", "deskwPomodoro", "deskwTodo"]);
    for (const i of w) {
        assert.match(i.id, /^dw_/);
        assert.equal(i.enabled, true);
        assert.equal(i.config.syncPositionAcrossScreens, true);
        const p = sess.desktopWidgetInstancePositions[i.id]._synced;
        assert.ok(p.x >= 0 && p.x < 1 && p.y >= 0 && p.y < 1, i.widgetType);
        assert.ok(p.width >= 160 && p.height >= 160, i.widgetType);
        // On screen, within a 1920×1080 one.
        const x = p.anchorX === "end" ? 1920 - p.width - p.x * 1920 : p.x * 1920;
        assert.ok(x >= 0 && x + p.width <= 1920 && p.y * 1080 + p.height <= 1080, i.widgetType);
    }
    assert.equal(sess.other, 1);
    // No two overlap (on a 1920×1080 screen).
    // As DMS reads it: anchorX "end" counts x from the right edge.
    const box = i => {
        const p = sess.desktopWidgetInstancePositions[i.id]._synced;
        const x = p.anchorX === "end" ? 1920 - p.width - p.x * 1920 : p.x * 1920;
        return [x, p.y * 1080, x + p.width, p.y * 1080 + p.height];
    };
    for (const a of w)
        for (const b of w)
            if (a !== b) {
                const [ax1, ay1, ax2, ay2] = box(a), [bx1, by1, bx2, by2] = box(b);
                assert.ok(ax2 <= bx1 || bx2 <= ax1 || ay2 <= by1 || by2 <= ay1, `${a.widgetType} overlaps ${b.widgetType}`);
            }
});

test("install twice adds nothing more, and a widget you already placed stays where it is", () => {
    const f = files({ desktopWidgetInstances: [{ id: "dw_mine", widgetType: "deskwClock", enabled: true, config: {} }] }, { desktopWidgetInstancePositions: { dw_mine: { _synced: { x: 0.5, y: 0.5 } } } });
    f.run("install");
    f.run("install");
    const [s, sess] = f.read();
    assert.equal(ours(s).length, 6);
    assert.equal(ours(s).filter(i => i.widgetType === "deskwClock").length, 1);
    assert.deepEqual(sess.desktopWidgetInstancePositions.dw_mine, { _synced: { x: 0.5, y: 0.5 } });
});

test("uninstall takes only Islet's widgets and their places away", () => {
    const f = files({ desktopWidgetInstances: [{ id: "dw_1", widgetType: "systemMonitor", enabled: true, config: {} }] }, {});
    f.run("install");
    f.run("uninstall");
    const [s, sess] = f.read();
    assert.deepEqual(s.desktopWidgetInstances.map(i => i.id), ["dw_1"]);
    assert.deepEqual(sess.desktopWidgetInstancePositions, {});
});

test("missing files: settings is required, a session file is made", () => {
    const f = files({}, undefined);
    f.run("install");
    const [s, sess] = f.read();
    assert.equal(ours(s).length, 6);
    assert.equal(Object.keys(sess.desktopWidgetInstancePositions).length, 6);
});

// Where each widget lands on a 1920×1080 screen, as DMS reads it.
function boxes(f) {
    const [s, sess] = f.read();
    return ours(s).map(i => {
        const p = sess.desktopWidgetInstancePositions[i.id]._synced;
        const x = p.anchorX === "end" ? 1920 - p.width - p.x * 1920 : p.x * 1920;
        return { type: i.widgetType, x1: x, y1: p.y * 1080, x2: x + p.width, y2: p.y * 1080 + p.height };
    });
}
const apart = list => list.every(a => list.every(b => a === b || a.x2 <= b.x1 || b.x2 <= a.x1 || a.y2 <= b.y1 || b.y2 <= a.y1));

test("with Islet's lyrics on the right, all six go on the left half, apart", () => {
    const f = files({}, {});
    f.run("install", "left");
    const b = boxes(f);
    assert.equal(b.length, 6);
    assert.ok(b.every(w => w.x1 >= 0 && w.x2 <= 960), JSON.stringify(b));
    assert.ok(apart(b));
});

test("with them on the left, all six go on the right half, apart", () => {
    const f = files({}, {});
    f.run("install", "right");
    const b = boxes(f);
    assert.ok(b.every(w => w.x1 >= 960 && w.x2 <= 1920), JSON.stringify(b));
    assert.ok(apart(b));
});
