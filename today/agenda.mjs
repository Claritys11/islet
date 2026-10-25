// Google Calendar events and Notion tasks on a given day, for the Today tab
// and the Calendar tab, plus the month grid. Plain functions; times are local.
import { dueDate } from "./deadlines.mjs";
import { TAG } from "./sync.mjs";

const SHORT = { id: ["Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"], en: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] };
const pad = n => String(n).padStart(2, "0");
// "08.00" in Indonesian, "08:00" in English (lang "en").
const hm = (d, lang) => `${pad(d.getHours())}${lang === "en" ? ":" : "."}${pad(d.getMinutes())}`;
const WORDS = {
    id: { allDay: "sepanjang hari", until: "s/d", untitled: "(tanpa judul)", due: "tenggat" },
    en: { allDay: "all day", until: "until", untitled: "(untitled)", due: "due" }
};
const words = lang => WORDS[lang === "en" ? "en" : "id"];

function startOfDay(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}
function addDays(d, n) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
}
export function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

// dcal gives an all-day event as UTC midnights of its dates, the end date
// exclusive (or equal to the start for a one-day event).
function localDate(iso) {
    const [y, m, d] = String(iso).slice(0, 10).split("-").map(Number);
    return new Date(y, m - 1, d);
}
function span(e) {
    if (!e.allDay)
        return { start: new Date(e.start), end: new Date(e.end) };
    const start = localDate(e.start), end = localDate(e.end);
    return { start, end: end > start ? end : addDays(start, 1) };
}

// Events touching `day`, Islet's own copies of Notion items left out, each
// with words for its time: "08.00–09.00", "20.00 →" (runs past midnight),
// "→ 20.00" (began before today), "sepanjang hari"; and `until` when it
// lasts beyond the day ("s/d Min 20.00").
export function eventsOn(events, day, now, calendars, lang = "id") {
    const w = words(lang), short = SHORT[lang === "en" ? "en" : "id"];
    const from = startOfDay(day), to = addDays(from, 1);
    const cal = {};
    for (const c of calendars ?? [])
        cal[c.id] = c;
    const seen = new Set();
    const out = [];
    for (const e of events) {
        if (String(e.description ?? "").includes(TAG))
            continue;
        const { start, end } = span(e);
        if (!(start < to && end > from))
            continue;
        const key = `gcal:${e.id}:${e.start}`;
        if (seen.has(key))
            continue;
        seen.add(key);
        const before = start < from, after = end > to;
        const time = e.allDay || (before && after) ? w.allDay : before ? `→ ${hm(end, lang)}` : after ? `${hm(start, lang)} →` : `${hm(start, lang)}–${hm(end, lang)}`;
        const last = e.allDay ? addDays(end, -1) : end;
        const c = cal[e.calendarId];
        out.push({
            key,
            id: e.id,
            title: e.summary || w.untitled,
            calendar: c?.name ?? "",
            color: c?.color || "#8ab4f8",
            readOnly: !!c?.readOnly,
            allDay: !!e.allDay,
            location: e.location ?? "",
            start,
            end,
            time,
            until: after ? `${w.until} ${short[last.getDay()]}${e.allDay ? "" : " " + hm(end, lang)}` : "",
            now: start <= now && now < end,
            past: end <= now
        });
    }
    return out.sort((a, b) => a.start - b.start || b.allDay - a.allDay);
}

// Unfinished Notion tasks due on `day`: timed ones by time, then the ones
// due "by the end of the day".
export function tasksOn(tasks, day, lang = "id") {
    return tasks.filter(t => !t.done && t.due && sameDay(dueDate(t.due), day)).map(t => ({
        key: `notion:${t.pageId}`,
        pageId: t.pageId,
        title: t.title,
        priority: t.priority ?? "",
        due: dueDate(t.due),
        time: t.dueHasTime ? hm(dueDate(t.due), lang) : words(lang).due
    })).sort((a, b) => a.due - b.due);
}

// The 42 days (six weeks, Monday first) shown for a month; `month` 0–11,
// and beyond rolls into the next year.
export function monthGrid(year, month) {
    const first = new Date(year, month, 1);
    const start = addDays(first, -((first.getDay() + 6) % 7));
    return Array.from({ length: 42 }, (_, i) => addDays(start, i));
}

const MONTH = { id: ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"], en: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"] };
// A time: "19.00", "7:30", "jam 16", "pukul 7.30" (4 groups).
const TIME = "(?:(?:jam|pukul)\\s*(\\d{1,2})(?:[.:](\\d{2}))?|(\\d{1,2})[.:](\\d{2}))";
const RANGE = new RegExp(`(^|\\s)${TIME}(?:\\s*(?:-|–|—|sampai|hingga|s/d)\\s*${TIME})?(?=\\s|$)`, "gi");

function clock(g) {
    const h = Number(g[0] ?? g[2]), m = Number(g[1] ?? g[3] ?? 0);
    return g[0] === undefined && g[2] === undefined || h > 23 || m > 59 ? null : { h, m };
}
const dateStamp = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T00:00:00Z`;

// "Rapat OSIS 19.00-20.30" on `day` → { title, allDay, start, end, label },
// times as dcal's events.create takes them (all-day: the dates, end
// exclusive). No time: all day; no end: `minutes` long; an end before the
// start: the next day. null when there's nothing to call it.
export function parseEvent(text, day, minutes, lang = "id") {
    const L = lang === "en" ? "en" : "id";
    let found = null, m;
    RANGE.lastIndex = 0;
    while (!found && (m = RANGE.exec(text))) {
        const a = clock(m.slice(2, 6)), b = clock(m.slice(6, 10));
        if (a)
            found = { a, b: m[6] !== undefined || m[8] !== undefined ? b : null, at: m.index, len: m[0].length };
    }
    const title = (found ? text.slice(0, found.at) + " " + text.slice(found.at + found.len) : text).replace(/\s+/g, " ").trim();
    if (!title)
        return null;
    const when = `${SHORT[L][day.getDay()]} ${day.getDate()} ${MONTH[L][day.getMonth()]}`;
    if (!found)
        return { title, allDay: true, start: dateStamp(day), end: dateStamp(addDays(day, 1)), label: `${when} · ${words(L).allDay}` };
    const start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), found.a.h, found.a.m);
    let end = found.b ? new Date(day.getFullYear(), day.getMonth(), day.getDate(), found.b.h, found.b.m) : new Date(start.getTime() + minutes * 60000);
    if (end <= start)
        end = new Date(end.getTime() + 864e5);
    return { title, allDay: false, start: start.toISOString(), end: end.toISOString(), label: `${when} · ${hm(start, L)}–${hm(end, L)}` };
}
