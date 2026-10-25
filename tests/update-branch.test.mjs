import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync, execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, symlinkSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const islet = new URL("../bin/islet", import.meta.url).pathname;
const git = (cwd, ...args) => execFileSync("git", ["-c", "user.email=t@t", "-c", "user.name=t", ...args], { cwd, encoding: "utf8" });

// A GitHub stand-in with main one release ahead, and Islet cloned from it
// into a fake ~/.config/quickshell/islet.
function setup() {
    const root = mkdtempSync(join(tmpdir(), "upd-"));
    const origin = join(root, "origin.git"), work = join(root, "work"), clone = join(root, "islet");
    git(root, "init", "-q", "--bare", "-b", "main", origin);
    git(root, "clone", "-q", origin, work);
    writeFileSync(join(work, "a"), "1");
    git(work, "add", "a"); git(work, "commit", "-qm", "one"); git(work, "tag", "v1.0.0"); git(work, "push", "-q", "origin", "main", "--tags");
    git(root, "clone", "-q", origin, clone);
    writeFileSync(join(work, "a"), "2");
    git(work, "commit", "-qam", "two"); git(work, "tag", "v1.1.0"); git(work, "push", "-q", "origin", "main", "--tags");
    const config = join(root, "config");
    mkdirSync(join(config, "quickshell"), { recursive: true });
    symlinkSync(clone, join(config, "quickshell", "islet"));
    const bin = join(root, "bin");
    mkdirSync(bin);
    writeFileSync(join(bin, "qs"), "#!/bin/sh\nexit 1\n");
    chmodSync(join(bin, "qs"), 0o755);
    const run = (...args) => spawnSync("sh", [islet, ...args], { env: { ...process.env, XDG_CONFIG_HOME: config, PATH: `${bin}:${process.env.PATH}` }, encoding: "utf8" });
    return { clone, run };
}

test("on main, --check sees the new release", () => {
    const { run } = setup();
    const r = run("update", "--check");
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /Update available: v1\.0\.0 → v1\.1\.0/);
});

test("on a branch that follows nothing, it says so instead of 'up to date'", () => {
    const { clone, run } = setup();
    git(clone, "switch", "-q", "-c", "my-work");
    const r = run("update", "--check");
    assert.notEqual(r.status, 0);
    assert.doesNotMatch(r.stdout + r.stderr, /up to date/);
    assert.match(r.stderr, /branch 'my-work'/);
    assert.match(r.stderr, /switch main/);
});
