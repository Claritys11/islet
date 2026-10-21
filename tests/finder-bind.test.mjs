import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const islet = new URL("../bin/islet", import.meta.url).pathname;
const sample = `// my binds
binds {
    Mod+B { spawn "zen-browser"; }
    Mod+C { spawn "code"; }
}
`;

function run(file) {
    return spawnSync("sh", [islet, "find", "bind", file], { env: { ...process.env, NIRI_VALIDATE: "true" }, encoding: "utf8" });
}

function setup(text) {
    const dir = mkdtempSync(join(tmpdir(), "niri-"));
    const file = join(dir, "user-binds.kdl");
    writeFileSync(file, text);
    return file;
}

test("adds Mod+G inside the binds block, once", () => {
    const file = setup(sample);
    const r = run(file);
    assert.equal(r.status, 0, r.stderr + r.stdout);
    const text = readFileSync(file, "utf8");
    const lines = text.split("\n");
    const at = lines.findIndex(l => l.includes('spawn "islet" "find"'));
    assert.ok(at > lines.indexOf("binds {") && at < lines.lastIndexOf("}"));
    assert.match(lines[at], /^\s+Mod\+G hotkey-overlay-title="Islet Finder" \{ spawn "islet" "find"; \}$/);
    const again = run(file);
    assert.equal(again.status, 0);
    assert.match(again.stdout, /already set up/);
    assert.equal(readFileSync(file, "utf8"), text);
});

test("refuses when Mod+G is taken, leaving the file alone", () => {
    const taken = sample.replace("Mod+C", "Mod+G");
    const file = setup(taken);
    const r = run(file);
    assert.notEqual(r.status, 0);
    assert.match(r.stdout + r.stderr, /Mod\+G/);
    assert.equal(readFileSync(file, "utf8"), taken);
});

test("restores the file when niri rejects it", () => {
    const file = setup(sample);
    const r = spawnSync("sh", [islet, "find", "bind", file], { env: { ...process.env, NIRI_VALIDATE: "false" }, encoding: "utf8" });
    assert.notEqual(r.status, 0);
    assert.equal(readFileSync(file, "utf8"), sample);
});
