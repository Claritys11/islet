// Pure helpers behind the socket fields the DankMaterialShell desktop widgets
// read (IsletLink.qml): a window of lyric lines, the open tasks, the focus
// timer, a month of calendar events, and Markdown → Notion blocks for new
// notes. No QML here, so `node --test tests/link-desk.test.mjs` covers it.

import { eventsOn } from "../today/agenda.mjs";

// The current line and a few around it, so a desktop card can show several
// lines without the whole song going out every 33 ms. `index` is the
// current line's place in the returned slice; -1 with no lines.
export function lyricWindow(lines, index, before = 2, after = 4) {
    if (!Array.isArray(lines) || lines.length === 0 || index < 0 || index >= lines.length)
        return { index: -1, lines: [] };
    const from = Math.max(0, index - before);
    const to = Math.min(lines.length, index + after + 1);
    return {
        index: index - from,
        lines: lines.slice(from, to).map(l => ({ t: l.time, text: l.main ?? "" }))
    };
}

// Tasks for the To-Do widget: open ones first, by due date (none last),
// then by title.
export function openTasks(tasks, limit = 40) {
    const rank = t => (t.due ? 0 : 1);
    return [...(tasks ?? [])]
        .sort((a, b) => (a.done - b.done) || (rank(a) - rank(b)) || String(a.due).localeCompare(String(b.due)) || String(a.title).localeCompare(String(b.title)))
        .slice(0, limit)
        .map(t => ({
            id: t.pageId,
            title: t.title,
            due: t.due ?? "",
            dueHasTime: !!t.dueHasTime,
            priority: t.priority ?? "",
            done: !!t.done,
            status: t.status ?? ""
        }));
}

// A due date sent with "task-add": Notion's date ("2026-11-05") or date and
// time with an offset ("2026-11-05T14:00:00+07:00"); anything else is "".
export function validDue(due) {
    const s = String(due ?? "");
    return /^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2})?(Z|[+-]\d{2}:\d{2}))?$/.test(s) && !isNaN(new Date(s.length === 10 ? s + "T00:00:00" : s)) ? s : "";
}

// The focus timer as the Pomodoro widget needs it; always present (the old
// `timer` field stays null while idle, which the bar widget relies on).
//
// Like the notch's Focus tab: whether it rolls on by itself (continuous),
// the round towards the long break, a tip on breaks, and this sitting. The
// pause and the sitting go as the times they began (ms), not as counters,
// so a paused timer doesn't send a line every second; the widgets count.
export function pomodoroView(p, o = {}) {
    return {
        active: !!p.active,
        mode: p.mode,
        label: p.label,
        clock: p.clock,
        running: !!p.running,
        paused: !!p.paused,
        progress: Math.round((p.progress ?? 0) * 1000) / 1000,
        todayCount: p.todayCount ?? 0,
        todayFocused: Math.floor((p.todayFocused ?? 0) / 60),
        continuous: !!p.continuous,
        round: p.round ?? 1,
        longEvery: o.longEvery ?? 4,
        tip: p.mode !== "focus" && o.breakTips && p.tip ? { icon: String(p.tip.icon ?? ""), text: String(p.tip.text ?? "") } : null,
        sessionStart: p.sessionStart ?? 0,
        pausedAt: p.paused ? (p._pausedAt ?? 0) : 0,
        // Seconds, without the pause going on now (pausedAt is that one).
        pausedBefore: Math.floor(p._pausedTotal ?? 0),
        focused: Math.floor(p.focused ?? 0)
    };
}

// The Hari ini tab for the DMS dashboard: today's lessons and events, close
// deadlines, the lesson about to start — plain values that survive JSON.
export function todayView(t) {
    return {
        enabled: !!t.enabled,
        status: t.status ?? "",
        error: t.error ?? "",
        sync: t.sync ?? "",
        canAdd: !!t.tasksDb,
        // The task list has a due date column, so new tasks can get one.
        canDue: !!t.tasksDb && !!t.dueColumn,
        // Daily tasks: a list exists, today's, and where to edit them.
        canDaily: !!t.dailyDb,
        dailyUrl: t.dailyDb ? `https://www.notion.so/${String(t.dailyDb).replace(/-/g, "")}` : "",
        daily: (t.daily ?? []).map(d => ({ id: d.id, title: d.title, time: d.time ?? "", done: !!d.done, late: !!d.late })),
        soon: t.soon ? { title: t.soon.title, startAt: t.soon.startAt } : null,
        schedule: (t.schedule ?? []).map(s => ({
            kind: s.kind,
            key: s.key,
            title: s.title,
            time: s.time,
            until: s.until ?? "",
            now: !!s.now,
            past: !!s.past,
            clash: !!s.clash,
            color: s.kind === "event" ? String(s.color ?? "") : ""
        })),
        deadlines: (t.deadlines ?? []).map(d => ({
            id: d.pageId ?? "",
            key: d.key,
            title: d.title,
            source: d.source,
            priority: d.priority ?? "",
            label: d.label,
            urgency: d.urgency,
            tickable: d.source === "notion"
        }))
    };
}

const PICTURE = /\.(png|jpe?g|gif|webp|bmp|svg|avif)$/i;

// The Shelf's files: name, folder or picture (for a thumbnail), gone missing.
export function shelfView(items) {
    return (items ?? []).map(i => ({
        path: i.path,
        name: i.name,
        dir: !!i.dir,
        image: !i.dir && PICTURE.test(i.name ?? ""),
        missing: !!i.missing
    }));
}

// The Checklist's to-dos, and whether they're in Notion or kept by Islet.
export function checklistView(items, notion, error) {
    return {
        source: notion ? "notion" : "local",
        error: error ?? "",
        items: (items ?? []).map(i => ({ id: String(i.id), text: i.text, checked: !!i.checked }))
    };
}

// A month of events (month0: 0 = January): how many per day, and the list
// for each day, worked out with the same rules as the Today tab.
export function monthEvents(events, year, month0, calendars, now, lang = "id") {
    const days = {}, byDay = {};
    const last = new Date(year, month0 + 1, 0).getDate();
    for (let d = 1; d <= last; d++) {
        const list = eventsOn(events ?? [], new Date(year, month0, d), now, calendars, lang);
        if (list.length === 0)
            continue;
        days[d] = list.length;
        byDay[d] = list.map(e => ({ time: e.time, title: e.title, color: e.color, calendar: e.calendar, allDay: e.allDay }));
    }
    return { days, byDay };
}

// The Markdown the Notes widget's toolbar writes, into Notion rich text:
// `**bold**`, `*italic*`, `~~strike~~`, `<u>underline</u>`, `` `code` ``
// and `[text](https://…)`, nested as typed (`**a *b* c**`). A marker with
// no closing partner, and a link that isn't http(s)/mailto, stay as typed.
const MARKS = [
    ["**", "**", "bold"],
    ["~~", "~~", "strikethrough"],
    ["<u>", "</u>", "underline"],
    ["*", "*", "italic"]
];

// Where `close` ends what opened before `from`; a lone `*` skips over the
// `**` pairs inside it so `*x **y** z*` closes at the last star.
function closeAt(text, from, close) {
    if (close !== "*")
        return text.indexOf(close, from);
    for (let j = from; j < text.length; j++) {
        if (text.startsWith("**", j)) {
            const end = text.indexOf("**", j + 2);
            if (end < 0)
                return -1;
            j = end + 1;
        } else if (text[j] === "*") {
            return j;
        }
    }
    return -1;
}

const LINK = /^\[([^\]\n]+)\]\(((?:https?:\/\/|mailto:)[^)\s]+)\)/;

export function inline(text, annotations = {}, link = null, out = []) {
    // Notion takes at most 2000 characters per rich text object.
    const push = content => {
        for (let i = 0; i < content.length; i += 2000) {
            const piece = { type: "text", text: { content: content.slice(i, i + 2000) },
                annotations: Object.assign({ bold: false, italic: false, strikethrough: false, underline: false, code: false }, annotations) };
            if (link)
                piece.text.link = { url: link };
            out.push(piece);
        }
    };
    let buf = "", i = 0;
    const flush = () => {
        if (buf !== "")
            push(buf);
        buf = "";
    };
    text = String(text ?? "");
    outer: while (i < text.length) {
        if (text[i] === "`") {
            const end = text.indexOf("`", i + 1);
            if (end > i + 1) {
                flush();
                inline(text.slice(i + 1, end), Object.assign({}, annotations, { code: true }), link, out);
                i = end + 1;
                continue;
            }
        }
        if (text[i] === "[" && !link) {
            const m = text.slice(i).match(LINK);
            if (m) {
                flush();
                inline(m[1], annotations, m[2], out);
                i += m[0].length;
                continue;
            }
        }
        for (const [open, close, key] of MARKS) {
            if (!text.startsWith(open, i))
                continue;
            const end = closeAt(text, i + open.length, close);
            if (end > i + open.length) {
                flush();
                inline(text.slice(i + open.length, end), Object.assign({}, annotations, { [key]: true }), link, out);
                i = end + close.length;
                continue outer;
            }
        }
        buf += text[i++];
    }
    flush();
    return out;
}

function block(type, text, extra = {}) {
    return { object: "block", type, [type]: Object.assign({ rich_text: inline(text) }, extra) };
}

// One line of a note: its indent level (two spaces or a tab each) and the
// block it makes.
function lineBlock(line) {
    const body = line.replace(/^\s+/, "");
    let m;
    if ((m = body.match(/^(#{1,3})\s+(.*)$/)))
        return block(`heading_${m[1].length}`, m[2]);
    if ((m = body.match(/^(?:[-*]\s+)?\[( |x|X)\]\s+(.*)$/)))
        return block("to_do", m[2], { checked: m[1] !== " " });
    if (/^(-{3,}|\*{3,})$/.test(body))
        return { object: "block", type: "divider", divider: {} };
    if ((m = body.match(/^[-*]\s+(.*)$/)))
        return block("bulleted_list_item", m[1]);
    if ((m = body.match(/^\d+[.)]\s+(.*)$/)))
        return block("numbered_list_item", m[1]);
    if ((m = body.match(/^>\s?(.*)$/)))
        return block("quote", m[1]);
    return block("paragraph", body);
}

const indentOf = line => {
    const lead = line.match(/^[ \t]*/)[0].replace(/\t/g, "  ");
    return Math.floor(lead.length / 2);
};

// Notion creates at most two levels of nested children in one request.
const MAX_DEPTH = 2;

// A note typed on the desktop: the first line is the title, the rest
// becomes blocks. Indented lines become children of the line above them.
export function markdownToBlocks(md) {
    const lines = String(md ?? "").split("\n");
    const first = lines.findIndex(l => l.trim() !== "");
    if (first < 0)
        throw new Error("empty note");
    const titleText = lines[first].trim().replace(/^#{1,3}\s+/, "").slice(0, 2000);
    const titleRich = inline(titleText);
    const title = titleRich.map(r => r.text.content).join("");
    const blocks = [];
    // The last block at each depth, to hang deeper lines under.
    const parents = [];
    const rest = lines.slice(first + 1);
    for (let n = 0; n < rest.length; n++) {
        const line = rest[n].replace(/\s+$/, "");
        if (line.trim() === "")
            continue;
        let b;
        if (line.trim().startsWith("```")) {
            const code = [];
            while (++n < rest.length && !rest[n].trim().startsWith("```"))
                code.push(rest[n]);
            b = block("code", code.join("\n"), { language: "plain text" });
            // Code is never parsed for ** or links.
            b.code.rich_text = [];
            const text = code.join("\n");
            for (let i = 0; i < text.length; i += 2000)
                b.code.rich_text.push({ type: "text", text: { content: text.slice(i, i + 2000) } });
        } else {
            b = lineBlock(line);
        }
        let depth = Math.min(indentOf(line), parents.length, MAX_DEPTH);
        if (depth > 0) {
            const parent = parents[depth - 1];
            const body = parent[parent.type];
            if (parent.type === "divider" || parent.type === "code" || parent.type.startsWith("heading")) {
                depth = 0;
            } else {
                if (!body.children)
                    body.children = [];
                body.children.push(b);
            }
        }
        if (depth === 0)
            blocks.push(b);
        parents.length = depth;
        parents[depth] = b;
    }
    return { title, titleRich, blocks };
}

// A page's blocks with all their children, any depth: `fetch(id, cursor,
// cb(ok, {results, has_more, next_cursor}))` is one Notion call. Child
// pages and databases aren't opened. Stops after `maxBlocks` (400) or
// `maxCalls` (60) and says so: cb(ok, blocks | error, cut).
export function walkBlocks(fetch, rootId, opts, cb) {
    const maxBlocks = opts?.maxBlocks ?? 400, maxCalls = opts?.maxCalls ?? 60;
    let count = 0, calls = 0, cut = false, failed = null, running = 0;
    const top = [];
    const finish = () => {
        if (--running > 0)
            return;
        if (failed !== null)
            cb(false, failed);
        else
            cb(true, top, cut);
    };
    const list = (id, into, isRoot) => {
        const page = cursor => {
            if (calls >= maxCalls || count >= maxBlocks) {
                cut = true;
                return finish();
            }
            calls++;
            fetch(id, cursor, (ok, res) => {
                if (!ok) {
                    if (isRoot)
                        failed = res;
                    return finish();
                }
                for (const b of res.results ?? []) {
                    if (count >= maxBlocks) {
                        cut = true;
                        break;
                    }
                    count++;
                    into.push(b);
                    if (b.has_children && b.type !== "child_page" && b.type !== "child_database") {
                        b.children = [];
                        running++;
                        list(b.id, b.children, false);
                    }
                }
                if (res.has_more && res.next_cursor && count < maxBlocks)
                    return page(res.next_cursor);
                if (res.has_more)
                    cut = true;
                finish();
            });
        };
        page(null);
    };
    running++;
    list(rootId, top, true);
}

// A list in pieces of at most n (Notion appends at most 100 blocks a call).
export function chunks(list, n) {
    const out = [];
    for (let i = 0; i < list.length; i += n)
        out.push(list.slice(i, i + n));
    return out;
}

// A command line from a socket client, or null when it isn't one.
export function parseCommand(line) {
    let msg;
    try {
        msg = JSON.parse(line);
    } catch (e) {
        return null;
    }
    return msg && typeof msg === "object" && typeof msg.cmd === "string" ? msg : null;
}
