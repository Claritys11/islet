import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, renameSync, statSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const script = new URL("../shelf/locate.sh", import.meta.url).pathname;

function home() {
    const root = mkdtempSync(join(tmpdir(), "shelf-"));
    for (const d of ["Downloads", "Documents/school", ".hidden"])
        mkdirSync(join(root, d), { recursive: true });
    return root;
}

const run = args => execFileSync("sh", [script, ...args], { encoding: "utf8" }).split("\n").filter(Boolean).map(l => l.split("\t"));

test("info gives each path's inode and whether it is a folder", () => {
    const root = home();
    const f = join(root, "Downloads", "tugas 1 $x.pdf");
    writeFileSync(f, "x");
    const dir = join(root, "Documents");
    assert.deepEqual(run(["info", f, dir]), [[f, String(statSync(f).ino), "0"], [dir, String(statSync(dir).ino), "1"]]);
});

test("a moved file is found again by its inode, even renamed", () => {
    const root = home();
    const before = join(root, "Downloads", "a.pdf");
    writeFileSync(before, "x");
    const ino = String(statSync(before).ino);
    const after = join(root, "Documents", "school", "b.pdf");
    renameSync(before, after);
    assert.deepEqual(run(["find", root, before, ino]), [[before, after]]);
});

test("files still in place print nothing", () => {
    const root = home();
    const f = join(root, "Downloads", "a.pdf");
    writeFileSync(f, "x");
    assert.deepEqual(run(["find", root, f, String(statSync(f).ino)]), []);
});

test("without an inode, a single file of the same name is taken", () => {
    const root = home();
    const before = join(root, "Downloads", "notes [1].txt");
    writeFileSync(join(root, "Documents", "notes [1].txt"), "x");
    assert.deepEqual(run(["find", root, before, ""]), [[before, join(root, "Documents", "notes [1].txt")]]);
});

test("two files of that name, or none, or only in hidden folders: not found", () => {
    const root = home();
    const before = join(root, "Downloads", "a.txt");
    writeFileSync(join(root, "Documents", "a.txt"), "x");
    writeFileSync(join(root, "Documents", "school", "a.txt"), "x");
    writeFileSync(join(root, ".hidden", "c.txt"), "x");
    const gone = join(root, "Downloads", "c.txt");
    const deleted = join(root, "Downloads", "d.txt");
    writeFileSync(deleted, "x");
    const ino = String(statSync(deleted).ino);
    rmSync(deleted);
    assert.deepEqual(run(["find", root, before, "", gone, "", deleted, ino]), [[before, ""], [gone, ""], [deleted, ""]]);
});
