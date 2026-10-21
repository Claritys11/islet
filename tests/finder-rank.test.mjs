import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fzfQuery, nameMatch, frecency, rank, recent, remember, shortPath, detect, actionCommand } from "../finder/rank.mjs";

const DAY = 864e5;

test("nameMatch finds abbreviations at word starts", () => {
    const m = nameMatch("isw", "islet-windows");
    assert.deepEqual(m.positions, [0, 1, 6]);
    assert.ok(m.score > nameMatch("isw", "chiswick").score);
    assert.equal(nameMatch("xyz", "islet-windows"), null);
    assert.ok(nameMatch("IW", "isletWindows"));
});

test("rank prefers projects and history", () => {
    const now = 100 * DAY;
    const entries = [
        { path: "/h/x/islet_swap.txt", kind: "file", project: false },
        { path: "/h/old/isw", kind: "dir", project: false },
        { path: "/h/Projects/islet-windows", kind: "dir", project: true },
    ];
    const history = { "/h/x/islet_swap.txt": { count: 1, last: now - 60 * DAY } };
    assert.ok(rank("isw", entries, history, now)[0].path.endsWith("islet-windows"));
});

test("rank keeps path-only matches, below name matches", () => {
    const entries = [
        { path: "/h/lyrics/notes.txt", kind: "file", project: false },
        { path: "/h/a/lyrics", kind: "dir", project: false },
    ];
    const r = rank("lyrics", entries, {}, 0);
    assert.equal(r.length, 2);
    assert.equal(r[0].path, "/h/a/lyrics");
    assert.deepEqual(r[1].positions, []);
});

test("frecency decays by half each week", () => {
    assert.equal(frecency({ count: 4, last: 0 }, 7 * DAY), 2);
    assert.equal(frecency(undefined, 0), 0);
});

test("remember counts and caps at 500", () => {
    let h = {};
    for (let i = 0; i < 520; i++)
        h = remember(h, { path: `/p/${i}`, kind: "file" }, i * 1000);
    assert.equal(Object.keys(h).length, 500);
    h = remember(h, { path: "/p/519", kind: "file" }, 600000);
    assert.equal(h["/p/519"].count, 2);
    assert.equal(h["/p/519"].last, 600000);
});

test("recent lists by frecency", () => {
    const h = { "/a": { count: 1, last: 0, kind: "dir" }, "/b": { count: 5, last: 0, kind: "file" } };
    assert.deepEqual(recent(h, 0).map(e => e.path), ["/b", "/a"]);
});

// Against the real fzf: operator characters are matched as typed.
function fzf(q, items) {
    try {
        return execFileSync("fzf", ["--filter", fzfQuery(q)], { input: items.join("\n") + "\n", encoding: "utf8", env: { PATH: process.env.PATH } }).split("\n").filter(Boolean);
    } catch {
        return [];
    }
}

test("fzfQuery matches operator characters literally", () => {
    const items = ["/a/!foo", "/a/bar$", "/a/'x", "/a/^y", "/a/a|b", "/a/plain"];
    assert.deepEqual(fzf("!foo", items), ["/a/!foo"]);
    assert.ok(fzf("bar$", items).includes("/a/bar$"));
    assert.deepEqual(fzf("'x", items), ["/a/'x"]);
    assert.deepEqual(fzf("^y", items), ["/a/^y"]);
    assert.ok(fzf("a | b", items).includes("/a/a|b"));
    assert.equal(fzfQuery("  a  b "), "a b");
});

test("actionCommand keeps odd paths as single args", () => {
    const entry = { path: "/h/my dir/-x $y'.txt", kind: "file" };
    const apps = { fileManager: "dolphin", terminal: "ghostty", editor: "code" };
    for (const a of ["open", "terminal", "editor", "reveal", "copy"]) {
        const cmd = actionCommand(a, entry, apps);
        assert.ok(cmd.every(x => typeof x === "string"), a);
        assert.ok(cmd.includes(entry.path) || cmd.includes("/h/my dir") || cmd.some(x => x.endsWith("=/h/my dir")), a);
    }
    assert.deepEqual(actionCommand("copy", entry, apps), ["wl-copy", "--", entry.path]);
    assert.deepEqual(actionCommand("reveal", entry, apps), ["dolphin", "--select", entry.path]);
    assert.deepEqual(actionCommand("open", { path: "/h/d", kind: "dir" }, { fileManager: "" }), ["xdg-open", "/h/d"]);
    assert.deepEqual(actionCommand("reveal", entry, { fileManager: "nautilus" }), ["nautilus", "/h/my dir"]);
});

test("terminal flags per terminal", () => {
    const dir = { path: "/h/p", kind: "dir" };
    assert.deepEqual(actionCommand("terminal", dir, { terminal: "ghostty" }), ["ghostty", "--working-directory=/h/p"]);
    assert.deepEqual(actionCommand("terminal", dir, { terminal: "konsole" }), ["konsole", "--workdir", "/h/p"]);
    assert.deepEqual(actionCommand("terminal", dir, { terminal: "kitty" }), ["kitty", "--directory", "/h/p"]);
    assert.deepEqual(actionCommand("terminal", { path: "/h/p/a.txt", kind: "file" }, { terminal: "foot" }), ["foot", "--working-directory=/h/p"]);
    assert.deepEqual(actionCommand("terminal", dir, { terminal: "wezterm" }), ["sh", "-c", 'cd "$1" && exec "$0"', "wezterm", "/h/p"]);
    assert.deepEqual(actionCommand("editor", dir, { editor: "code" }), ["code", "/h/p"]);
});

test("shortPath and detect", () => {
    assert.equal(shortPath("/home/u/a", "/home/u"), "~/a");
    assert.equal(shortPath("/home/u", "/home/u"), "~");
    assert.equal(shortPath("/home/uu/a", "/home/u"), "/home/uu/a");
    assert.equal(detect(["ghostty", "kitty"], ["kitty", "ghostty"]), "ghostty");
    assert.equal(detect(["zed"], []), "");
});
