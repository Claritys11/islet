import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, symlinkSync, lstatSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const islet = new URL("../bin/islet", import.meta.url).pathname;

// A qs that always fails: if a test ever reaches a command that talks to
// Islet, it must not open anything on the real desktop.
const fakeBin = mkdtempSync(join(tmpdir(), "fakeqs-"));
writeFileSync(join(fakeBin, "qs"), "#!/bin/sh\nexit 1\n");
chmodSync(join(fakeBin, "qs"), 0o755);
process.env.PATH = `${fakeBin}:${process.env.PATH}`;
const sample = `// my binds
binds {
    Mod+B { spawn "zen-browser"; }
    Mod+C { spawn "code"; }
}
`;

function run(file) {
    return spawnSync("sh", [islet, "find", "--bind", file], { env: { ...process.env, NIRI_VALIDATE: "true" }, encoding: "utf8" });
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
    const r = spawnSync("sh", [islet, "find", "--bind", file], { env: { ...process.env, NIRI_VALIDATE: "false" }, encoding: "utf8" });
    assert.notEqual(r.status, 0);
    assert.equal(readFileSync(file, "utf8"), sample);
});

test("without user-binds.kdl it uses niri's config.kdl", () => {
    const home = mkdtempSync(join(tmpdir(), "xdg-"));
    const dir = join(home, "niri");
    mkdirSync(dir);
    writeFileSync(join(dir, "config.kdl"), sample);
    const r = spawnSync("sh", [islet, "find", "--bind"], { env: { ...process.env, XDG_CONFIG_HOME: home, NIRI_VALIDATE: "true" }, encoding: "utf8" });
    assert.equal(r.status, 0, r.stderr + r.stdout);
    assert.match(readFileSync(join(dir, "config.kdl"), "utf8"), /spawn "islet" "find"/);
});

test("errors go to stdout too, so Settings can show them", () => {
    const r = spawnSync("sh", [islet, "find", "--bind", "/nonexistent/binds.kdl"], { env: { ...process.env, NIRI_VALIDATE: "true" }, encoding: "utf8" });
    assert.notEqual(r.status, 0);
    assert.match(r.stdout, /No niri binds file/);
});

test("keeps a symlinked binds file a symlink", () => {
    const dir = mkdtempSync(join(tmpdir(), "niri-"));
    const real = join(dir, "dotfiles-binds.kdl");
    writeFileSync(real, sample);
    const link = join(dir, "user-binds.kdl");
    symlinkSync(real, link);
    assert.equal(run(link).status, 0);
    assert.ok(lstatSync(link).isSymbolicLink());
    assert.match(readFileSync(real, "utf8"), /spawn "islet" "find"/);
});

test("finds the end of the binds block even when the brace is indented", () => {
    const text = "binds {\n    Mod+B { spawn \"b\"; }\n  }\nlayout {\n    gaps 8\n}\n";
    const file = setup(text);
    assert.equal(run(file).status, 0);
    const lines = readFileSync(file, "utf8").split("\n");
    const at = lines.findIndex(l => l.includes('"islet" "find"'));
    assert.ok(at > 0 && at < lines.indexOf("layout {"), lines.join("\n"));
});

test("Super+G counts as taken too", () => {
    const taken = sample.replace("Mod+C", "Super+G");
    const file = setup(taken);
    assert.notEqual(run(file).status, 0);
    assert.equal(readFileSync(file, "utf8"), taken);
});
