import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, copyFileSync, writeFileSync, chmodSync, rmSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const script = join(dirname(fileURLToPath(import.meta.url)), "../today/dcal-heal.sh");

// A pretend `dcal` for the script to call, logging what it's asked; and a
// process named dcal whose binary has been replaced (or not).
function setup() {
    const dir = mkdtempSync(join(tmpdir(), "islet-heal-"));
    const bin = join(dir, "bin");
    spawnSync("mkdir", [bin]);
    const log = join(dir, "log");
    writeFileSync(join(bin, "dcal"), `#!/bin/sh\necho "$*" >> "${log}"\n`);
    chmodSync(join(bin, "dcal"), 0o755);
    writeFileSync(join(bin, "systemd-run"), `#!/bin/sh\necho "systemd-run $*" >> "${log}"\n`);
    chmodSync(join(bin, "systemd-run"), 0o755);
    return { dir, bin, log };
}
const run = bin => spawnSync("sh", [script], { env: { ...process.env, PATH: `${bin}:${process.env.PATH}` } });
function daemon(dir, deleted) {
    const named = join(dir, "dcal");
    copyFileSync("/usr/bin/sleep", named);
    chmodSync(named, 0o755);
    const proc = spawn(named, ["30"], { stdio: "ignore" });
    if (deleted)
        rmSync(named);
    return proc;
}

test("dcal-heal: a daemon on a replaced binary is started again, hidden", async () => {
    const { dir, bin, log } = setup();
    const proc = daemon(dir, true);
    await new Promise(r => setTimeout(r, 100));
    run(bin);
    proc.kill();
    assert.deepEqual(readFileSync(log, "utf8").trim().split("\n"), ["kill", "systemd-run --user --collect --quiet -p ExitType=cgroup dcal run -d --hidden"]);
});

test("dcal-heal: a current daemon is left alone", async () => {
    const { dir, bin, log } = setup();
    const proc = daemon(dir, false);
    await new Promise(r => setTimeout(r, 100));
    run(bin);
    proc.kill();
    assert.equal(existsSync(log), false);
});
