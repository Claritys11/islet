import { test } from "node:test";
import assert from "node:assert/strict";
import { wrap, setBlock, link, onEnter, indent, diff, draftTitle } from "../integrations/dms/desk/common/mdedit.mjs";

// "a[b]c" → text with the selection marked, for readable assertions.
const show = r => r.text.slice(0, r.start) + "[" + r.text.slice(r.start, r.end) + "]" + r.text.slice(r.end);

test("wrap: selection gets the marker, and again takes it off", () => {
    const on = wrap("ini tebal ya", 4, 9, "**");
    assert.equal(show(on), "ini **[tebal]** ya");
    assert.equal(show(wrap(on.text, on.start, on.end, "**")), "ini [tebal] ya");
    // Selecting the markers too also unwraps.
    assert.equal(show(wrap("ini **tebal** ya", 4, 13, "**")), "ini [tebal] ya");
});

test("wrap: no selection puts the cursor between a new pair", () => {
    assert.equal(show(wrap("ab", 1, 1, "<u>", "</u>")), "a<u>[]</u>b");
});

test("setBlock: heading on the cursor's line, toggled off, replacing a list prefix", () => {
    assert.equal(setBlock("judul\nisi", 2, 2, "h1").text, "# judul\nisi");
    assert.equal(setBlock("# judul\nisi", 3, 3, "h1").text, "judul\nisi");
    assert.equal(setBlock("- item", 3, 3, "h2").text, "## item");
});

test("setBlock: several lines become a numbered list, indent kept", () => {
    const r = setBlock("a\n  b\nc", 0, 7, "number");
    assert.equal(r.text, "1. a\n  2. b\n3. c");
    assert.equal(setBlock("- [ ] x\n- [ ] y", 0, 13, "todo").text, "x\ny");
    assert.equal(setBlock("x", 0, 0, "todo").text, "- [ ] x");
    assert.equal(setBlock("x", 0, 0, "quote").text, "> x");
});

test("link: selected text becomes [text](https://) with the URL selected", () => {
    const r = link("lihat situs ini", 6, 11);
    assert.equal(show(r), "lihat [situs]([https://]) ini");
    const empty = link("", 0, 0);
    assert.equal(show(empty), "[[teks]](https://)");
});

test("onEnter: continues bullets, numbers and to-dos; an empty item ends the list", () => {
    assert.equal(show(onEnter("- satu", 6)), "- satu\n- []");
    assert.equal(show(onEnter("  3. tiga", 9)), "  3. tiga\n  4. []");
    assert.equal(show(onEnter("- [x] beres", 11)), "- [x] beres\n- [ ] []");
    assert.equal(show(onEnter("a\n- ", 4)), "a\n[]");
    assert.equal(onEnter("biasa", 5), null);
    // In the middle of a line, Enter is left to the editor.
    assert.equal(onEnter("- satu", 3), null);
});

test("indent: Tab adds two spaces to every selected line, Shift+Tab takes them off", () => {
    assert.equal(indent("- a\n- b", 0, 7, 1).text, "  - a\n  - b");
    assert.equal(indent("  - a\n- b", 0, 9, -1).text, "- a\n- b");
    const r = indent("- a", 3, 3, 1);
    assert.equal(r.start, 5);
});

test("diff: the smallest replace that turns one text into the other", () => {
    assert.deepEqual(diff("abcdef", "abXYef"), { at: 2, remove: 2, insert: "XY" });
    assert.deepEqual(diff("abc", "abc"), { at: 3, remove: 0, insert: "" });
    assert.deepEqual(diff("aaa", "aaaa"), { at: 3, remove: 0, insert: "a" });
});

test("draftTitle: first line without markers, cut at 28 characters", () => {
    assert.equal(draftTitle("\n# Ide **besar**\nisi"), "Ide besar");
    assert.equal(draftTitle("- [ ] tugas"), "tugas");
    assert.equal(draftTitle(""), "");
    assert.equal(draftTitle("x".repeat(40)), "x".repeat(27) + "…");
});
