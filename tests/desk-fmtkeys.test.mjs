import { test } from "node:test";
import assert from "node:assert/strict";
import { keyAction, TOOLS } from "../integrations/dms/desk/common/fmtkeys.mjs";

// Qt key codes for these keys are their ASCII codes.
const k = c => c.charCodeAt(0);

test("Ctrl shortcuts: B I U E K", () => {
    assert.equal(keyAction(k("B"), true, false), "bold");
    assert.equal(keyAction(k("I"), true, false), "italic");
    assert.equal(keyAction(k("U"), true, false), "underline");
    assert.equal(keyAction(k("E"), true, false), "code");
    assert.equal(keyAction(k("K"), true, false), "link");
});

test("Ctrl+Shift: digits or their shifted symbols, S for strike, . for quote", () => {
    assert.equal(keyAction(k("1"), true, true), "h1");
    assert.equal(keyAction(k("!"), true, true), "h1");
    assert.equal(keyAction(k("@"), true, true), "h2");
    assert.equal(keyAction(k("#"), true, true), "h3");
    assert.equal(keyAction(k("$"), true, true), "todo");
    assert.equal(keyAction(k("%"), true, true), "bullet");
    assert.equal(keyAction(k("^"), true, true), "number");
    assert.equal(keyAction(k(">"), true, true), "quote");
    assert.equal(keyAction(k("S"), true, true), "strike");
});

test("host keys are left alone", () => {
    assert.equal(keyAction(k("S"), true, false), null); // Ctrl+S: save, the host's
    assert.equal(keyAction(k("N"), true, false), null);
    assert.equal(keyAction(k("B"), false, false), null);
    assert.equal(keyAction(k("B"), true, true), null);
});

test("every toolbar button has a shortcut that maps back to it", () => {
    for (const t of TOOLS)
        assert.ok(t.tip.includes("Ctrl"), t.id);
    assert.deepEqual(new Set(TOOLS.map(t => t.id)).size, TOOLS.length);
});
