import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const script = new URL("../finder/index.sh", import.meta.url).pathname;

function tree() {
    const root = mkdtempSync(join(tmpdir(), "finder-"));
    for (const f of ["a/proj/.git/HEAD", "a/proj/src/main.c", "a/node_modules/x/y.js", "a/.hidden/z.txt", "a/my file's $x.txt"]) {
        mkdirSync(join(root, f, ".."), { recursive: true });
        writeFileSync(join(root, f), "");
    }
    return root;
}

function build(root, hidden) {
    const out = mkdtempSync(join(tmpdir(), "finder-out-"));
    execFileSync("sh", [script, out, hidden, "node_modules,.git", root]);
    const read = n => readFileSync(join(out, n), "utf8").split("\n").filter(Boolean);
    return { dirs: read("dirs.txt"), files: read("files.txt"), projects: read("projects.txt") };
}

test("indexes folders and files, skipping excluded and hidden ones", () => {
    const root = tree();
    const { dirs, files, projects } = build(root, "0");
    assert.ok(dirs.includes(`${root}/a/proj`));
    assert.ok(!dirs.some(d => d.includes("node_modules")));
    assert.ok(files.includes(`${root}/a/my file's $x.txt`));
    assert.ok(files.includes(`${root}/a/proj/src/main.c`));
    assert.ok(!files.some(f => f.includes(".hidden") || f.includes("/.git")));
    assert.deepEqual(projects, [`${root}/a/proj`]);
});

test("includes hidden files when asked, but never .git contents", () => {
    const root = tree();
    const { files } = build(root, "1");
    assert.ok(files.includes(`${root}/a/.hidden/z.txt`));
    assert.ok(!files.some(f => f.includes("/.git/")));
});

test("excludes are not globbed against the working folder, and are trimmed", () => {
    const root = tree();
    for (const f of ["a/notes.log", "a/sub/keep.txt"]) {
        mkdirSync(join(root, f, ".."), { recursive: true });
        writeFileSync(join(root, f), "");
    }
    const cwd = mkdtempSync(join(tmpdir(), "finder-cwd-"));
    writeFileSync(join(cwd, "x.log"), "");
    const out = mkdtempSync(join(tmpdir(), "finder-out-"));
    execFileSync("sh", [script, out, "0", "*.log, sub ,node_modules", root], { cwd });
    const files = readFileSync(join(out, "files.txt"), "utf8");
    assert.ok(!files.includes("notes.log"), "*.log should be skipped");
    assert.ok(!files.includes("/sub/"), "' sub ' should be trimmed and skipped");
});

test("a bad root fails and keeps the old index", () => {
    const root = tree();
    const out = mkdtempSync(join(tmpdir(), "finder-out-"));
    execFileSync("sh", [script, out, "0", "", root]);
    const before = readFileSync(join(out, "files.txt"), "utf8");
    let failed = false;
    try {
        execFileSync("sh", [script, out, "0", "", join(root, "does-not-exist")], { stdio: "pipe" });
    } catch {
        failed = true;
    }
    assert.ok(failed, "should exit non-zero");
    assert.equal(readFileSync(join(out, "files.txt"), "utf8"), before);
});
