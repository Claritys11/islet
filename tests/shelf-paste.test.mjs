import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const script = new URL("../shelf/paste.sh", import.meta.url).pathname;

// A clipboard: a fake wl-paste on PATH serving `types` and their contents.
function clipboard(types) {
    const root = mkdtempSync(join(tmpdir(), "paste-"));
    const bin = join(root, "bin"), clip = join(root, "clip"), out = join(root, "out");
    for (const d of [bin, clip, out])
        mkdirSync(d);
    writeFileSync(join(clip, "_types"), Object.keys(types).join("\n") + (Object.keys(types).length ? "\n" : ""));
    for (const [t, data] of Object.entries(types))
        writeFileSync(join(clip, t.replace(/[/;=]/g, "_")), data);
    writeFileSync(join(bin, "wl-paste"), `#!/bin/sh
dir=${JSON.stringify(clip)}
case "$1" in
  --list-types|-l) cat "$dir/_types"; exit 0 ;;
esac
t=""; while [ $# -gt 0 ]; do case "$1" in -t|--type) t="$2"; shift ;; esac; shift; done
f="$dir/$(printf %s "$t" | tr '/;=' '___')"
[ -f "$f" ] || exit 1
cat "$f"
`);
    chmodSync(join(bin, "wl-paste"), 0o755);
    const run = () => execFileSync("sh", [script, out], { encoding: "utf8", env: { ...process.env, PATH: `${bin}:${process.env.PATH}` } }).split("\n").filter(Boolean);
    return { root, out, run };
}

test("copied files (a file manager's uri-list) come out as paths, spaces and all", () => {
    const c = clipboard({ "text/uri-list": "file:///home/a/Tugas%20Akhir.pdf\r\n# comment\r\nfile:///home/a/foto.jpg\r\n" });
    assert.deepEqual(c.run(), ["/home/a/Tugas Akhir.pdf", "/home/a/foto.jpg"]);
    assert.deepEqual(readdirSync(c.out), []);
});

test("GNOME's copied-files list works too (its first line says copy or cut)", () => {
    const c = clipboard({ "x-special/gnome-copied-files": "copy\nfile:///home/a/x.txt" });
    assert.deepEqual(c.run(), ["/home/a/x.txt"]);
});

test("a picture (a screenshot) is saved as a PNG and that file comes out", () => {
    const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0xff]);
    const c = clipboard({ "image/png": png });
    const [p] = c.run();
    assert.match(p, /\/Tempelan [0-9-]+ [0-9.]+\.png$/);
    assert.ok(p.startsWith(c.out + "/"));
    assert.deepEqual(readFileSync(p), png);
});

test("other picture types keep their extension", () => {
    const c = clipboard({ "image/jpeg": "jpg" });
    assert.match(c.run()[0], /\.jpg$/);
});

test("plain text that is a path to a file is that file", () => {
    const c = clipboard({ "text/plain": script + "\n" });
    assert.deepEqual(c.run(), [script]);
});

test("other text is saved as a .txt named after its first words", () => {
    const c = clipboard({ "text/plain;charset=utf-8": "Rumus luas: p × l\nbaris dua", "text/plain": "x" });
    const [p] = c.run();
    assert.match(p, /\/Rumus luas p × l\.txt$/);
    assert.equal(readFileSync(p, "utf8"), "Rumus luas: p × l\nbaris dua");
});

test("a second paste of the same text doesn't overwrite the first", () => {
    const c = clipboard({ "text/plain": "catatan" });
    const a = c.run()[0], b = c.run()[0];
    assert.notEqual(a, b);
    assert.equal(readdirSync(c.out).length, 2);
});

test("an empty clipboard prints nothing and fails", () => {
    const c = clipboard({});
    assert.throws(() => c.run());
});
