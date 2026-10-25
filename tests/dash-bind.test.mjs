import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const islet = new URL("../bin/islet", import.meta.url).pathname;
// Fake qs and dms that fail: nothing may reach the real desktop.
const fakeBin = mkdtempSync(join(tmpdir(), "fakeqs-"));
for (const b of ["qs", "dms"]) {
    writeFileSync(join(fakeBin, b), "#!/bin/sh\nexit 1\n");
    chmodSync(join(fakeBin, b), 0o755);
}
const env = { ...process.env, PATH: `${fakeBin}:${process.env.PATH}`, NIRI_VALIDATE: "true" };

function setup(text) {
    const file = join(mkdtempSync(join(tmpdir(), "niri-")), "user-binds.kdl");
    writeFileSync(file, text);
    return file;
}
const run = (file, key) => spawnSync("sh", [islet, "dms", "bind", file].concat(key ? [key] : []), { env, encoding: "utf8" });

test("Mod+Z opens DMS's dashboard (its Island) on the overview, added once", () => {
    const file = setup("binds {\n    Mod+B { spawn \"zen-browser\"; }\n}\n");
    const r = run(file);
    assert.equal(r.status, 0, r.stdout + r.stderr);
    const text = readFileSync(file, "utf8");
    assert.match(text, /^    Mod\+Z hotkey-overlay-title="DMS Overview" \{ spawn "dms" "ipc" "call" "dash" "toggle" "overview"; \}$/m);
    assert.ok(text.indexOf("Mod+Z") < text.lastIndexOf("}"));
    assert.equal(run(file).status, 0);
    assert.equal(readFileSync(file, "utf8").match(/"dash" "toggle"/g).length, 1);
});

test("another key can be asked for", () => {
    const file = setup("binds {\n}\n");
    assert.equal(run(file, "Mod+Shift+O").status, 0);
    assert.match(readFileSync(file, "utf8"), /Mod\+Shift\+O hotkey-overlay-title="DMS Overview"/);
});

test("a key that's taken is refused and the file left alone", () => {
    const before = "binds {\n    Mod+Z { spawn \"zed\"; }\n}\n";
    const file = setup(before);
    const r = run(file);
    assert.notEqual(r.status, 0);
    assert.match(r.stdout, /Mod\+Z is already used/);
    assert.equal(readFileSync(file, "utf8"), before);
});
