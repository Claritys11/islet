import { parseJam, hariIndex, HARI } from "./timetable.mjs";

// Notion side of "Today": which databases are the timetable and the task
// list, which columns mean what, and rows as plain objects. Plain functions
// so Node can test them and QML can import them.

const WEEKDAYS = ["senin", "selasa", "rabu", "kamis", "jumat", "sabtu", "minggu", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];

const DONE_BOX = /^(selesai|done|centang|ceklis|checked?)$/i;

function titleOf(db) {
    return (db.title ?? []).map(t => t.plain_text).join("");
}

function entries(properties) {
    return Object.entries(properties ?? {}).map(([name, p]) => ({ name, type: p.type, p }));
}

function looksLikeWeekdays(p) {
    const opts = (p.select?.options ?? p.multi_select?.options ?? []).map(o => o.name.toLowerCase().replace(/['’\s]/g, ""));
    return opts.filter(o => WEEKDAYS.includes(o)).length >= 3;
}

// What a database is, judged by its columns: a weekly timetable (a weekday
// select and a time text) or a task list (a title, a status and a date).
// The score breaks ties between look-alikes.
export function classify(db) {
    const props = entries(db.properties);
    const has = (type, re) => props.some(e => e.type === type && (!re || re.test(e.name)));
    const title = titleOf(db);
    const recent = Date.parse(db.last_edited_time ?? 0) / 1e12;
    if (props.some(e => e.type === "select" && looksLikeWeekdays(e.p)) && props.some(e => (e.type === "rich_text" || e.type === "title") && /jam|waktu|time/i.test(e.name)))
        return { kind: "timetable", score: 1 + (/jadwal|timetable|schedule/i.test(title) ? 1 : 0) + recent };
    // Daily tasks: which days (several of a weekday list) and a tick. Islet
    // takes old ticks off by itself, so only its own list is found by itself:
    // any other has to be picked in Settings.
    if (/^daily tasks$/i.test(title.trim()) && has("title") && props.some(e => e.type === "multi_select" && looksLikeWeekdays(e.p)) && has("checkbox", DONE_BOX))
        return { kind: "daily", score: 1 + recent };
    if (has("title") && (has("status") || has("select", /status/i)) && has("date"))
        return { kind: "tasks", score: 1 + (/task|tugas/i.test(title) ? 1 : 0) + (has("date", /tenggat|deadline|due/i) ? 1 : 0) + recent };
    return { kind: null, score: 0 };
}

export function pickDatabases(dbs) {
    const best = { timetable: { id: "", score: -1 }, tasks: { id: "", score: -1 }, daily: { id: "", score: -1 } };
    for (const db of dbs) {
        const c = classify(db);
        if (c.kind && c.score > best[c.kind].score)
            best[c.kind] = { id: db.id, score: c.score };
    }
    return { timetable: best.timetable.id, tasks: best.tasks.id, daily: best.daily.id };
}

// Column names for each meaning; "" when there's none.
export function mapColumns(kind, properties) {
    const props = entries(properties);
    const find = (types, re) => (props.find(e => types.includes(e.type) && (!re || re.test(e.name))) ?? { name: "" }).name;
    if (kind === "timetable") {
        const hari = (props.find(e => e.type === "select" && looksLikeWeekdays(e.p)) ?? { name: "" }).name;
        return {
            title: find(["title"]),
            hari,
            jam: find(["rich_text", "title"], /jam|waktu|time/i),
            mapel: find(["relation", "select", "rich_text"], /mapel|pelajaran|subject|course/i),
            guru: find(["rich_text", "people", "select"], /guru|teacher|pengajar/i)
        };
    }
    if (kind === "daily") {
        return {
            title: find(["title"]),
            days: (props.find(e => e.type === "multi_select" && looksLikeWeekdays(e.p)) ?? { name: "" }).name,
            time: find(["rich_text"], /jam|waktu|time/i),
            done: find(["checkbox"], DONE_BOX),
            off: find(["checkbox"], /nonaktif|libur|jeda|off|pause/i)
        };
    }
    const dates = props.filter(e => e.type === "date");
    const start = (dates.find(e => /rencana|mulai|start|plan|kerjakan/i.test(e.name)) ?? { name: "" }).name;
    const due = (dates.find(e => /tenggat|deadline|due|kumpul/i.test(e.name)) ?? dates.find(e => e.name !== start) ?? { name: "" }).name;
    return {
        title: find(["title"]),
        status: find(["status"]) || find(["select"], /status/i),
        start,
        due,
        priority: find(["select"], /prior/i),
        type: find(["select"], /tipe|type|kategori|category/i),
        gcal: find(["rich_text"], /gcal|google/i)
    };
}

function text(prop) {
    if (!prop)
        return "";
    const parts = prop[prop.type] ?? [];
    if (prop.type === "select" || prop.type === "status")
        return parts?.name ?? "";
    return Array.isArray(parts) ? parts.map(t => t.plain_text ?? "").join("") : "";
}

// A timetable row → Lesson, named after its subject (the related page's
// title) when there is one.
export function lessonFromRow(row, map, mapelTitles) {
    const p = row.properties;
    const jam = text(p[map.jam]);
    const time = parseJam(jam);
    if (!time)
        return { error: `Jam “${jam}” isn't a time like 07.00-08.30`, pageId: row.id };
    const day = hariIndex(text(p[map.hari]));
    if (day < 0)
        return { error: `Hari “${text(p[map.hari])}” isn't a weekday`, pageId: row.id };
    const mapel = p[map.mapel];
    const subject = mapel?.type === "relation" ? (mapel.relation ?? []).map(r => mapelTitles[r.id]).filter(Boolean).join(", ") : text(mapel);
    return {
        pageId: row.id,
        title: subject || text(p[map.title]),
        hari: HARI[day],
        start: time.start,
        end: time.end,
        guru: text(p[map.guru]),
        edited: Date.parse(row.last_edited_time)
    };
}

const DONE = /^(done|selesai|complete|completed|finished|beres)$/i;

export function taskFromRow(row, map) {
    const p = row.properties;
    const date = name => p[name]?.date ?? null;
    const start = date(map.start), due = date(map.due);
    return {
        pageId: row.id,
        title: text(p[map.title]),
        status: text(p[map.status]),
        done: DONE.test(text(p[map.status])),
        start: start?.start ?? "",
        startHasTime: (start?.start ?? "").includes("T"),
        end: start?.end ?? "",
        due: due?.start ?? "",
        dueHasTime: (due?.start ?? "").includes("T"),
        priority: text(p[map.priority]),
        type: text(p[map.type]),
        gcalId: text(p[map.gcal]),
        edited: Date.parse(row.last_edited_time)
    };
}

const richText = s => [{ type: "text", text: { content: s } }];

// Notion `properties` for the given changes; unset fields are left alone.
// `map.statusType` is "select" when the Status column is a select rather
// than Notion's status type.
export function taskPatch(map, fields) {
    const out = {};
    if (fields.title !== undefined && map.title)
        out[map.title] = { title: richText(fields.title) };
    if (fields.status !== undefined && map.status)
        out[map.status] = map.statusType === "select" ? { select: { name: fields.status } } : { status: { name: fields.status } };
    if (fields.start !== undefined && map.start)
        out[map.start] = { date: fields.start ? { start: fields.start, end: fields.end || null } : null };
    if (fields.gcalId !== undefined && map.gcal)
        out[map.gcal] = { rich_text: fields.gcalId ? richText(fields.gcalId) : [] };
    return out;
}

// Whether a request may be sent again when its connection dropped before an
// answer (Notion closes idle HTTP/2 connections; the next request on one
// fails): reads, and changes that end the same however often they're made.
// A new page or appended blocks are not: twice would mean two of them.
export function retryable(method, path) {
    if (method === "GET" || method === "DELETE")
        return true;
    if (method === "PATCH")
        return !/\/children$/.test(path);
    if (method === "POST")
        return path === "search" || /\/query$/.test(path);
    return false;
}

// ── Daily tasks ───────────────────────────────────────────────────
// Rows of a list of things to do on certain days, each with a tick that can
// be set here or in Notion. A tick counts on the day its row was last edited;
// one left from an earlier day is taken off (dailyStale) whenever Islet
// loads: when it starts, past midnight, and at each sync. Nothing needs to be
// running at midnight, and every computer sees the same.

const pad = n => String(n).padStart(2, "0");
const isoDay = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const JS_DAY = { minggu: 0, sunday: 0, senin: 1, monday: 1, selasa: 2, tuesday: 2, rabu: 3, wednesday: 3, kamis: 4, thursday: 4, jumat: 5, friday: 5, sabtu: 6, saturday: 6 };

export function dailyFromRow(row, map) {
    const p = row.properties;
    const days = (p[map.days]?.multi_select ?? []).map(o => JS_DAY[o.name.toLowerCase().replace(/['’\s]/g, "")]).filter(d => d !== undefined);
    const t = /(\d{1,2})[.:](\d{2})/.exec(text(p[map.time]));
    return {
        pageId: row.id,
        title: text(p[map.title]).trim(),
        days,
        time: t && +t[1] < 24 && +t[2] < 60 ? `${pad(+t[1])}.${t[2]}` : "",
        checked: !!p[map.done]?.checkbox,
        edited: Date.parse(row.last_edited_time),
        off: !!p[map.off]?.checkbox
    };
}

const doneOn = (item, today) => item.checked && isoDay(new Date(item.edited)) === today;

// What's on for `now`'s day (no days chosen: every day): what's left first,
// by time, untimed after; plain values. `late`: its time has gone by.
export function dailyToday(items, now, lang = "id") {
    const today = isoDay(now), clock = `${pad(now.getHours())}.${pad(now.getMinutes())}`;
    return (items ?? [])
        .filter(i => !i.off && i.title !== "" && (i.days.length === 0 || i.days.includes(now.getDay())))
        .map(i => {
            const done = doneOn(i, today);
            return { id: i.pageId, title: i.title, time: lang === "en" ? i.time.replace(".", ":") : i.time, sort: i.time, done, late: !done && i.time !== "" && i.time < clock };
        })
        .sort((a, b) => (a.done - b.done) || ((a.sort === "") - (b.sort === "")) || a.sort.localeCompare(b.sort) || a.title.localeCompare(b.title))
        .map(i => ({ id: i.id, title: i.title, time: i.time, done: i.done, late: i.late }));
}

// Ticks left from an earlier day, on any row: these get taken off.
export function dailyStale(items, now) {
    const today = isoDay(now);
    return (items ?? []).filter(i => i.checked && !doneOn(i, today)).map(i => i.pageId);
}

// Notion `properties` to set or take off a tick.
export function dailyPatch(map, done) {
    return { [map.done]: { checkbox: !!done } };
}
