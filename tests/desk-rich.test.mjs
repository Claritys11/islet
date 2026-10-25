import { test } from "node:test";
import assert from "node:assert/strict";
import { blocksToRich, richToHtml, monthGrid, safeLink, notionAppUrl } from "../integrations/dms/desk/common/rich.mjs";

const t = (content, ann = {}, href = null) => ({ type: "text", plain_text: content, href, text: { content, link: href ? { url: href } : null }, annotations: Object.assign({ bold: false, italic: false, strikethrough: false, underline: false, code: false }, ann) });

test("richToHtml: bold and link, escaped", () => {
    assert.equal(richToHtml([t("x", { bold: true }), t(" "), t("y", {}, "https://n")]), '<b>x</b> <a href="https://n">y</a>');
    assert.equal(richToHtml([t("<script>&")]), "&lt;script&gt;&amp;");
    assert.equal(richToHtml([t("c", { code: true, italic: true })]), "<i><tt>c</tt></i>");
});

test("blocksToRich: types kept, to_do checked, children deeper, unknown → paragraph", () => {
    const blocks = [
        { type: "heading_2", heading_2: { rich_text: [t("H")] } },
        { type: "to_do", to_do: { rich_text: [t("done")], checked: true } },
        { type: "bulleted_list_item", bulleted_list_item: { rich_text: [t("a")] }, children: [
            { type: "bulleted_list_item", bulleted_list_item: { rich_text: [t("b")] } }] },
        { type: "weird_block", weird_block: { rich_text: [t("odd")] } },
        { type: "divider", divider: {} }
    ];
    const r = blocksToRich(blocks);
    assert.deepEqual(r.map(x => x.type), ["heading_2", "to_do", "bulleted_list_item", "bulleted_list_item", "paragraph", "divider"]);
    assert.equal(r[1].checked, true);
    assert.equal(r[2].depth, 0);
    assert.equal(r[3].depth, 1);
    assert.equal(r[4].html, "odd");
    assert.equal(r[0].html, "H");
});

test("blocksToRich: numbered items get their number", () => {
    const n = s => ({ type: "numbered_list_item", numbered_list_item: { rich_text: [t(s)] } });
    const r = blocksToRich([n("a"), n("b"), { type: "paragraph", paragraph: { rich_text: [t("p")] } }, n("c")]);
    assert.deepEqual(r.filter(x => x.type === "numbered_list_item").map(x => x.number), [1, 2, 1]);
});

test("monthGrid: Monday start, 6 rows, padding days marked", () => {
    const g = monthGrid(2026, 9, 1); // October 2026 starts on a Thursday
    assert.equal(g.length, 42);
    assert.equal(g[0].inMonth, false);
    assert.equal(g[3].day, 1);
    assert.equal(g[3].inMonth, true);
    assert.equal(g.filter(c => c.inMonth).length, 31);
    const s = monthGrid(2026, 9, 0); // Sunday start
    assert.equal(s[4].day, 1);
});

test("M8: only http(s), mailto and notion links stay clickable", () => {
    assert.equal(safeLink("https://a.b/c"), "https://a.b/c");
    assert.equal(safeLink("mailto:x@y.z"), "mailto:x@y.z");
    assert.equal(safeLink("notion://www.notion.so/x"), "notion://www.notion.so/x");
    assert.equal(safeLink("file:///etc/passwd"), null);
    assert.equal(safeLink("javascript:alert(1)"), null);
    assert.equal(richToHtml([t("bad", {}, "file:///etc/passwd")]), "bad");
});

test("notionAppUrl: notion.so pages → notion://, other URLs → null", () => {
    assert.equal(notionAppUrl("https://www.notion.so/Ide-abc123"), "notion://www.notion.so/Ide-abc123");
    assert.equal(notionAppUrl("https://app.notion.com/p/Workspace-3f9d"), "notion://app.notion.com/p/Workspace-3f9d");
    assert.equal(notionAppUrl("https://example.com/x"), null);
    assert.equal(notionAppUrl(""), null);
});

test("M3: callout/toggle children, columns flattened, images, tables, bookmarks, child pages", () => {
    const p = s => ({ type: "paragraph", paragraph: { rich_text: [t(s)] } });
    const blocks = [
        { type: "callout", callout: { rich_text: [t("hati")], icon: { emoji: "💡" } }, children: [p("isi callout")] },
        { type: "column_list", column_list: {}, children: [
            { type: "column", column: {}, children: [p("kiri")] },
            { type: "column", column: {}, children: [p("kanan")] }] },
        { type: "image", image: { type: "file", caption: [t("foto")] } },
        { type: "table", table: {}, children: [
            { type: "table_row", table_row: { cells: [[t("a")], [t("b")]] } }] },
        { type: "bookmark", bookmark: { url: "https://x.id", caption: [] } },
        { type: "child_page", child_page: { title: "Sub" } },
        { type: "equation", equation: { expression: "e=mc^2" } }
    ];
    const r = blocksToRich(blocks);
    const html = r.map(x => x.html);
    assert.deepEqual(html.slice(0, 4), ["💡 hati", "isi callout", "kiri", "kanan"]);
    assert.equal(r[1].depth, 1);
    assert.equal(r[2].depth, 0);
    assert.equal(html[4], "🖼 foto");
    assert.equal(html[5], "a  │  b");
    assert.equal(html[6], '🔗 <a href="https://x.id">https://x.id</a>');
    assert.equal(html[7], "📄 Sub");
    assert.equal(html[8], "<tt>e=mc^2</tt>");
});

test("M3: blocks with nothing to show are dropped, not blank lines", () => {
    const r = blocksToRich([{ type: "unsupported", unsupported: {} }, { type: "paragraph", paragraph: { rich_text: [] } }]);
    assert.deepEqual(r.map(x => x.type), ["paragraph"]);
});
