// Notion blocks → Qt StyledText for the Notes desktop widget, and the month
// grid for the Calendar widget. Pure, so `node --test tests/` covers it.

const escape = s => String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

// A link the widget may open, or null: never file:, javascript: and the
// like (review M8).
export function safeLink(url) {
    return typeof url === "string" && /^(https?:\/\/|mailto:|notion:\/\/)/i.test(url) ? url : null;
}

// The Notion desktop app's deep link for a Notion page URL, or null when
// it isn't one.
export function notionAppUrl(url) {
    const m = String(url ?? "").match(/^https?:\/\/((?:www\.)?notion\.so|app\.notion\.com)(\/.*)?$/i);
    return m ? `notion://${m[1]}${m[2] ?? ""}` : null;
}

// One Notion rich_text array → StyledText (b, i, s, u, tt, a href).
export function richToHtml(rich) {
    return (rich ?? []).map(r => {
        const a = r.annotations ?? {};
        let s = escape(r.plain_text ?? r.text?.content ?? "");
        if (a.code) s = `<tt>${s}</tt>`;
        if (a.bold) s = `<b>${s}</b>`;
        if (a.italic) s = `<i>${s}</i>`;
        if (a.strikethrough) s = `<s>${s}</s>`;
        if (a.underline) s = `<u>${s}</u>`;
        const href = safeLink(r.href ?? r.text?.link?.url);
        if (href) s = `<a href="${escape(href)}">${s}</a>`;
        return s;
    }).join("");
}

const KNOWN = new Set(["paragraph", "heading_1", "heading_2", "heading_3", "bulleted_list_item",
    "numbered_list_item", "to_do", "quote", "callout", "toggle", "code", "divider"]);
// Containers with nothing of their own: their children are shown in place.
const FLAT = new Set(["column_list", "column", "synced_block", "table"]);

// What a block that isn't text shows as one line, or null.
function special(b) {
    const body = b[b.type] ?? {};
    switch (b.type) {
    case "image":
    case "video":
    case "file":
    case "pdf":
    case "audio": {
        const icon = { image: "🖼", video: "🎞", audio: "🎵" }[b.type] ?? "📎";
        const caption = richToHtml(body.caption);
        return `${icon} ${caption || body.name || b.type}`;
    }
    case "table_row":
        return (body.cells ?? []).map(richToHtml).join("  │  ");
    case "bookmark":
    case "embed":
    case "link_preview": {
        const url = safeLink(body.url);
        const caption = richToHtml(body.caption);
        return url ? `🔗 <a href="${escape(url)}">${caption || escape(url)}</a>` : null;
    }
    case "child_page":
        return `📄 ${escape(body.title)}`;
    case "child_database":
        return `🗃 ${escape(body.title)}`;
    case "equation":
        return `<tt>${escape(body.expression)}</tt>`;
    }
    return null;
}

// Blocks (with optional `children`, any depth) → a flat list the widget
// draws line by line: {type, html, depth, checked?, number?}. Unknown
// types show their text if they carry any, and are dropped if not.
export function blocksToRich(blocks, depth = 0) {
    const out = [];
    let number = 0;
    for (const b of blocks ?? []) {
        if (FLAT.has(b.type)) {
            number = 0;
            out.push(...blocksToRich(b.children, depth));
            continue;
        }
        const body = b[b.type] ?? {};
        const extra = special(b);
        const type = KNOWN.has(b.type) ? b.type : "paragraph";
        number = type === "numbered_list_item" ? number + 1 : 0;
        const html = extra ?? richToHtml(body.rich_text);
        if (extra === null && !KNOWN.has(b.type) && html === "" && !b.children?.length)
            continue;
        const item = { type, html, depth };
        if (type === "to_do") item.checked = !!body.checked;
        if (type === "numbered_list_item") item.number = number;
        if (type === "callout" && body.icon?.emoji) item.html = `${escape(body.icon.emoji)} ${item.html}`;
        out.push(item);
        if (b.children?.length)
            out.push(...blocksToRich(b.children, depth + 1));
    }
    return out;
}

// 6 weeks × 7 days for (year, month0); weekStart 1 = Monday, 0 = Sunday.
// Each cell: {day, inMonth, date: "YYYY-MM-DD"}.
export function monthGrid(year, month0, weekStart = 1) {
    const first = new Date(year, month0, 1);
    const lead = (first.getDay() - weekStart + 7) % 7;
    const cells = [];
    for (let i = 0; i < 42; i++) {
        const d = new Date(year, month0, 1 - lead + i);
        const pad = n => String(n).padStart(2, "0");
        cells.push({
            day: d.getDate(),
            inMonth: d.getMonth() === month0,
            date: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
        });
    }
    return cells;
}
