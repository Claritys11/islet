process.env.TZ = "Asia/Jakarta";
import { test } from "node:test";
import assert from "node:assert/strict";
import { lyricWindow, openTasks, pomodoroView, monthEvents, markdownToBlocks, parseCommand, chunks, inline, walkBlocks } from "../link/desk.mjs";

test("lyricWindow keeps 2 before and 4 after and re-bases the index", () => {
    const lines = Array.from({ length: 10 }, (_, i) => ({ time: i * 5, main: "l" + i }));
    const w = lyricWindow(lines, 5);
    assert.deepEqual(w.lines.map(l => l.text), ["l3", "l4", "l5", "l6", "l7", "l8", "l9"]);
    assert.equal(w.index, 2);
    assert.equal(w.lines[2].t, 25);
});

test("lyricWindow at the start and with nothing", () => {
    assert.equal(lyricWindow([{ time: 0, main: "a" }, { time: 1, main: "b" }], 0).index, 0);
    assert.deepEqual(lyricWindow([], 3), { index: -1, lines: [] });
    assert.deepEqual(lyricWindow([{ time: 0, main: "a" }], -1), { index: -1, lines: [] });
});

test("openTasks: not done first, by due, empty due last", () => {
    const t = [
        { pageId: "a", title: "z", due: "", done: false },
        { pageId: "b", title: "y", due: "2026-10-26", done: false },
        { pageId: "c", title: "x", due: "2026-10-25", done: true },
        { pageId: "d", title: "w", due: "2026-10-25", done: false }
    ];
    assert.deepEqual(openTasks(t).map(x => x.id), ["d", "b", "a", "c"]);
    assert.equal(openTasks(t, 2).length, 2);
});

test("pomodoroView rounds progress and gives minutes", () => {
    const v = pomodoroView({ active: true, mode: "focus", label: "Focus", clock: "24:59", running: true, paused: false, progress: 0.123456, todayCount: 2, todayFocused: 3010 });
    assert.equal(v.progress, 0.123);
    assert.equal(v.todayFocused, 50);
    assert.equal(v.clock, "24:59");
});

test("monthEvents counts per day and lists them", () => {
    const cals = [{ id: "me", name: "me@school", color: "#9fe1e7", readOnly: false }];
    const ev = (id, start, end) => ({ id, calendarId: "me", summary: id, start, end, allDay: false, description: "" });
    const evs = [ev("a", "2026-10-23T02:00:00Z", "2026-10-23T03:00:00Z"), ev("b", "2026-10-23T05:00:00Z", "2026-10-23T06:00:00Z")];
    const m = monthEvents(evs, 2026, 9, cals, new Date(2026, 9, 23, 12));
    assert.equal(m.days[23], 2);
    assert.equal(m.byDay[23].length, 2);
    assert.equal(m.byDay[23][0].title, "a");
    assert.equal(m.days[22], undefined);
});

test("markdownToBlocks: title, heading, list, todo, inline bold, unclosed stays", () => {
    const r = markdownToBlocks("# Ide\n## Sub\n- satu **dua**\n[x] beres\nteks *miring\n");
    assert.equal(r.title, "Ide");
    assert.deepEqual(r.blocks.map(b => b.type), ["heading_2", "bulleted_list_item", "to_do", "paragraph"]);
    assert.equal(r.blocks[1].bulleted_list_item.rich_text[1].annotations.bold, true);
    assert.equal(r.blocks[1].bulleted_list_item.rich_text[1].text.content, "dua");
    assert.equal(r.blocks[2].to_do.checked, true);
    assert.equal(r.blocks[3].paragraph.rich_text[0].text.content, "teks *miring");
    assert.throws(() => markdownToBlocks("  \n "), /empty note/);
});

test("markdownToBlocks: code, italic, numbered, quote", () => {
    const r = markdownToBlocks("Judul\n1. pertama\n> kutip\npakai `ls` dan *ini*");
    assert.deepEqual(r.blocks.map(b => b.type), ["numbered_list_item", "quote", "paragraph"]);
    const rt = r.blocks[2].paragraph.rich_text;
    assert.equal(rt.find(x => x.text.content === "ls").annotations.code, true);
    assert.equal(rt.find(x => x.text.content === "ini").annotations.italic, true);
});

test("parseCommand", () => {
    assert.equal(parseCommand("nope"), null);
    assert.equal(parseCommand('{"x":1}'), null);
    assert.deepEqual(parseCommand('{"cmd":"task-add","text":"a"}'), { cmd: "task-add", text: "a" });
});

test("markdownToBlocks splits text over Notion's 2000-character limit (I5)", () => {
    const long = "a".repeat(4500);
    const r = markdownToBlocks("Judul " + "t".repeat(2100) + "\n" + long);
    assert.ok(r.title.length <= 2000);
    const rt = r.blocks[0].paragraph.rich_text;
    assert.equal(rt.map(x => x.text.content).join(""), long);
    assert.ok(rt.every(x => x.text.content.length <= 2000));
});

test("chunks cuts a list into pieces of at most n (I5: 100 blocks per request)", () => {
    assert.deepEqual(chunks([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
    assert.deepEqual(chunks([], 100), []);
    assert.equal(chunks(Array(250).fill(0), 100).length, 3);
});

const ann = (rt, content) => rt.find(x => x.text.content === content)?.annotations;

test("inline: strikethrough, underline, nested bold+italic, link (toolbar output)", () => {
    const rt = inline("~~lama~~ <u>garis</u> **a *b* c** [situs](https://x.id/p)");
    assert.equal(ann(rt, "lama").strikethrough, true);
    assert.equal(ann(rt, "garis").underline, true);
    assert.equal(ann(rt, "a ").bold, true);
    assert.deepEqual([ann(rt, "b").bold, ann(rt, "b").italic], [true, true]);
    const link = rt.find(x => x.text.content === "situs");
    assert.equal(link.text.link.url, "https://x.id/p");
});

test("inline: italic around bold, and a link with a bad scheme stays text", () => {
    const rt = inline("*x **y** z* [no](javascript:alert(1))");
    assert.equal(ann(rt, "x ").italic, true);
    assert.deepEqual([ann(rt, "y").italic, ann(rt, "y").bold], [true, true]);
    assert.equal(rt.some(x => x.text.link), false);
    assert.match(rt.map(x => x.text.content).join(""), /\[no\]\(javascript:alert\(1\)\)/);
});

test("markdownToBlocks: GitHub '- [ ]' to-do, divider, fenced code", () => {
    const r = markdownToBlocks("T\n- [ ] belum\n- [x] sudah\n---\n```\nls -la\ncd ~\n```");
    assert.deepEqual(r.blocks.map(b => b.type), ["to_do", "to_do", "divider", "code"]);
    assert.equal(r.blocks[0].to_do.checked, false);
    assert.equal(r.blocks[1].to_do.checked, true);
    assert.equal(r.blocks[3].code.rich_text[0].text.content, "ls -la\ncd ~");
    assert.equal(r.blocks[3].code.language, "plain text");
});

test("markdownToBlocks: indented items become children (two levels, deeper is clamped)", () => {
    const r = markdownToBlocks("T\n- a\n  - b\n    - c\n      - d\n- e\n  teks");
    assert.deepEqual(r.blocks.map(b => b.type), ["bulleted_list_item", "bulleted_list_item"]);
    const a = r.blocks[0].bulleted_list_item;
    assert.equal(a.children.length, 1);
    const b = a.children[0].bulleted_list_item;
    assert.deepEqual(b.children.map(x => x.bulleted_list_item.rich_text[0].text.content), ["c", "d"]);
    assert.equal(r.blocks[1].bulleted_list_item.children[0].type, "paragraph");
});

test("markdownToBlocks: the title keeps its formatting as rich text", () => {
    const r = markdownToBlocks("# Ide **besar**\nisi");
    assert.equal(r.title, "Ide besar");
    assert.equal(ann(r.titleRich, "besar").bold, true);
});

// A fake Notion: pages of children, keyed by parent id and cursor.
function fakeNotion(tree, pageSize = 2) {
    const calls = [];
    const fetch = (id, cursor, cb) => {
        calls.push(id);
        const all = tree[id] ?? [];
        const from = cursor ? Number(cursor) : 0;
        const results = all.slice(from, from + pageSize);
        const more = from + pageSize < all.length;
        setTimeout(() => cb(true, { results, has_more: more, next_cursor: more ? String(from + pageSize) : null }), 0);
    };
    return { fetch, calls };
}

test("walkBlocks: pages through children and nests any depth (M3)", async () => {
    const blk = (id, kids) => ({ id, type: "paragraph", has_children: !!kids });
    const tree = { root: [blk("1"), blk("2", true), blk("3"), blk("4", true), blk("5")], 2: [blk("2a", true)], "2a": [blk("2a1")], 4: [blk("4a"), blk("4b"), blk("4c")] };
    const { fetch } = fakeNotion(tree);
    const out = await new Promise(res => walkBlocks(fetch, "root", {}, (ok, blocks) => res(blocks)));
    assert.deepEqual(out.map(b => b.id), ["1", "2", "3", "4", "5"]);
    assert.equal(out[1].children[0].children[0].id, "2a1");
    assert.deepEqual(out[3].children.map(b => b.id), ["4a", "4b", "4c"]);
});

test("walkBlocks: stops at the block cap and skips child pages", async () => {
    const tree = { root: Array.from({ length: 9 }, (_, i) => ({ id: "b" + i, type: i === 0 ? "child_page" : "paragraph", has_children: i === 0 })) };
    const { fetch, calls } = fakeNotion(tree);
    const out = await new Promise(res => walkBlocks(fetch, "root", { maxBlocks: 5 }, (ok, blocks, cut) => res({ blocks, cut })));
    assert.equal(out.blocks.length, 5);
    assert.equal(out.cut, true);
    assert.equal(calls.includes("b0"), false);
});

test("walkBlocks: a failing first page is an error", async () => {
    const out = await new Promise(res => walkBlocks((id, c, cb) => cb(false, "nope"), "root", {}, (ok, data) => res({ ok, data })));
    assert.deepEqual(out, { ok: false, data: "nope" });
});
