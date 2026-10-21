import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync, execSync } from "node:child_process";
import { mkdtempSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const script = new URL("../finder/search.sh", import.meta.url).pathname;

function index(lines) {
    const dir = mkdtempSync(join(tmpdir(), "finder-search-"));
    const file = join(dir, "files.txt");
    writeFileSync(file, lines.join("\n") + "\n");
    return file;
}

test("prints the search number first, then the matches", () => {
    const file = index(["/h/islet-windows", "/h/other"]);
    const r = spawnSync("sh", [script, "42", "isw", file], { encoding: "utf8" });
    assert.equal(r.status, 0);
    const lines = r.stdout.trim().split("\n");
    assert.equal(lines[0], "42");
    assert.deepEqual(lines.slice(1), ["/h/islet-windows"]);
});

test("a missing index answers with just the number", () => {
    const r = spawnSync("sh", [script, "7", "x", "/nonexistent/files.txt"], { encoding: "utf8" });
    assert.equal(r.stdout, "7\n");
});

test("ignores FZF_DEFAULT_OPTS", () => {
    const file = index(["/h/islet-windows"]);
    const r = spawnSync("sh", [script, "1", "isw", file], { encoding: "utf8", env: { ...process.env, FZF_DEFAULT_OPTS: "--exact" } });
    assert.deepEqual(r.stdout.trim().split("\n"), ["1", "/h/islet-windows"]);
});

test("stopping it stops fzf too", async () => {
    // A stand-in fzf that runs for a long time, marked so it can be found.
    const bin = mkdtempSync(join(tmpdir(), "fakefzf-"));
    const marker = `fakefzf-${process.pid}-${Date.now()}`;
    writeFileSync(join(bin, "fzf"), `#!/bin/sh\nexec -a ${marker} sleep 30\n`);
    chmodSync(join(bin, "fzf"), 0o755);
    const file = index(["/h/a"]);
    const child = spawn("sh", [script, "1", "a", file], { env: { ...process.env, PATH: `${bin}:${process.env.PATH}` } });
    await new Promise(r => setTimeout(r, 300));
    const running = () => { try { return execSync(`pgrep -f ${marker}`).toString().trim() !== ""; } catch { return false; } };
    assert.ok(running(), "the stand-in fzf should be running");
    child.kill("SIGTERM");
    await new Promise(r => setTimeout(r, 300));
    assert.ok(!running(), "fzf should be gone after SIGTERM");
});
