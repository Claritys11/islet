// A task's due date typed in plain words ("besok", "jum 14.00", "5/11",
// "12 des", "+3") turned into what Notion's date property takes, and a due
// date shown back as a short chip. Shared by the DMS widgets and Islet's
// notch. Plain functions; times are local.

const DAYS = [
    ["min", "minggu", "sun", "sunday"],
    ["sen", "senin", "mon", "monday"],
    ["sel", "selasa", "tue", "tues", "tuesday"],
    ["rab", "rabu", "wed", "wednesday"],
    ["kam", "kamis", "thu", "thur", "thurs", "thursday"],
    ["jum", "jumat", "jum'at", "fri", "friday"],
    ["sab", "sabtu", "sat", "saturday"]
];
const MONTHS = [
    ["jan", "januari", "january"],
    ["feb", "februari", "february", "pebruari"],
    ["mar", "maret", "march"],
    ["apr", "april"],
    ["mei", "may"],
    ["jun", "juni", "june"],
    ["jul", "juli", "july"],
    ["agu", "agt", "ags", "agustus", "aug", "august"],
    ["sep", "sept", "september"],
    ["okt", "oktober", "oct", "october"],
    ["nov", "november", "nop", "nopember"],
    ["des", "desember", "dec", "december"]
];
const SHORT = {
    id: { days: ["Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"], months: ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"] },
    en: { days: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], months: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"] }
};
const pad = n => String(n).padStart(2, "0");

function day(d, plus = 0) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + plus);
}

function dayIndex(word) {
    return DAYS.findIndex(names => names.includes(word));
}

function monthIndex(word) {
    return MONTHS.findIndex(names => names.includes(word));
}

// "5/11" or "5 nov" without a year: this year, or next if that's gone by.
function dayOfMonth(d, m, y, today) {
    const year = y ? (y < 100 ? 2000 + y : y) : today.getFullYear();
    let date = new Date(year, m, d);
    if (date.getMonth() !== m || date.getDate() !== d)
        return null;
    if (!y && date < today)
        date = new Date(year + 1, m, d);
    return date;
}

// The time out of the text ("14.00", "14:30", "jam 9", "9pm"), and the rest.
function takeTime(text) {
    let m = /(?:^|\s)(?:jam|pukul|pkl|at)\s*(\d{1,2})(?:[.:](\d{2}))?\s*(am|pm)?(?=\s|$)/.exec(text)
        ?? /(?:^|\s)(\d{1,2})[.:](\d{2})\s*(am|pm)?(?=\s|$)/.exec(text)
        ?? /(?:^|\s)(\d{1,2})()\s*(am|pm)(?=\s|$)/.exec(text);
    if (!m)
        return { rest: text, time: null };
    let h = +m[1];
    const min = m[2] ? +m[2] : 0;
    if (m[3] === "pm" && h < 12)
        h += 12;
    if (m[3] === "am" && h === 12)
        h = 0;
    if (h > 23 || min > 59)
        return { rest: text, time: undefined };
    return { rest: (text.slice(0, m.index) + " " + text.slice(m.index + m[0].length)).trim(), time: [h, min] };
}

// The day out of what's left once the time is taken.
function takeDay(text, today) {
    if (text === "")
        return null;
    if (/^(hari ini|hr ini|today|tdy|hariini)$/.test(text))
        return today;
    if (/^(besok|bsk|besuk|tomorrow|tmr|tmrw)$/.test(text))
        return day(today, 1);
    if (/^(lusa)$/.test(text))
        return day(today, 2);
    if (/^(minggu depan|pekan depan|next week)$/.test(text))
        return day(today, 7);
    let m = /^\+?(\d{1,3})\s*(hari|hr|h|days?|d)$/.exec(text) ?? /^\+(\d{1,3})$/.exec(text);
    if (m)
        return day(today, +m[1]);
    m = /^(\d{1,3})\s*(minggu|pekan|weeks?|w)$/.exec(text);
    if (m)
        return day(today, 7 * m[1]);
    // A weekday: the next one, a week on if it's today ("jumat depan" too).
    m = /^(?:next\s+)?([a-z']+)(?:\s+(depan|next))?$/.exec(text);
    if (m && dayIndex(m[1]) >= 0) {
        const ahead = (dayIndex(m[1]) - today.getDay() + 7) % 7 || 7;
        return day(today, ahead);
    }
    // 2026-11-05
    m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(text);
    if (m)
        return dayOfMonth(+m[3], +m[2] - 1, +m[1], today);
    // 5/11, 5-11-2026 ("5.11" is a time, as Indonesians write it)
    m = /^(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2}|\d{4}))?$/.exec(text);
    if (m)
        return dayOfMonth(+m[1], +m[2] - 1, m[3] ? +m[3] : 0, today);
    // 5 nov, 5 november 2026
    m = /^(\d{1,2})\s+([a-z]+)(?:\s+(\d{4}))?$/.exec(text);
    if (m && monthIndex(m[2]) >= 0)
        return dayOfMonth(+m[1], monthIndex(m[2]), m[3] ? +m[3] : 0, today);
    // nov 5
    m = /^([a-z]+)\s+(\d{1,2})(?:,?\s+(\d{4}))?$/.exec(text);
    if (m && monthIndex(m[1]) >= 0)
        return dayOfMonth(+m[2], monthIndex(m[1]), m[3] ? +m[3] : 0, today);
    // Just a day of the month: "15" is the next 15th.
    m = /^(?:tgl|tanggal)?\s*(\d{1,2})$/.exec(text);
    if (m && +m[1] >= 1 && +m[1] <= 31) {
        for (let k = 0; k < 3; k++) {
            const d = new Date(today.getFullYear(), today.getMonth() + k, +m[1]);
            if (d.getDate() === +m[1] && d >= today)
                return d;
        }
    }
    return null;
}

function offset(d) {
    const o = -d.getTimezoneOffset();
    return `${o < 0 ? "-" : "+"}${pad(Math.floor(Math.abs(o) / 60))}:${pad(Math.abs(o) % 60)}`;
}

// What was typed in the due field → { due, hasTime } for Notion ("2026-11-05",
// or "2026-11-05T14:00:00+07:00" with a time), { due: "" } when it's empty,
// or null when the words aren't a date. A time alone ("jam 14") is today's.
export function parseDue(text, now = new Date()) {
    const s = String(text ?? "").toLowerCase().replace(/,/g, " ").replace(/\s+/g, " ").trim();
    if (s === "" || /^(-|tanpa|none|no|nggak|gak)$/.test(s))
        return { due: "", hasTime: false };
    const today = day(now);
    const { rest, time } = takeTime(s);
    if (time === undefined)
        return null;
    const date = rest === "" && time ? today : takeDay(rest, today);
    if (!date)
        return null;
    const iso = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    if (!time)
        return { due: iso, hasTime: false };
    const at = new Date(date.getFullYear(), date.getMonth(), date.getDate(), time[0], time[1]);
    return { due: `${iso}T${pad(time[0])}:${pad(time[1])}:00${offset(at)}`, hasTime: true };
}

// A due date from Notion ("2026-11-05" or with a time) as a Date; date-only
// means the end of that day.
export function dueAt(due) {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(due ?? "");
    return m ? new Date(+m[1], +m[2] - 1, +m[3], 23, 59, 59) : new Date(due);
}

// A due date as a short chip: "Hari ini", "Besok 14.00", "Jum 7 Nov",
// "Terlambat" (late is true then). "" for no date.
export function dueChip(due, now = new Date(), lang = "id") {
    if (!due)
        return { text: "", late: false };
    const at = dueAt(due);
    if (isNaN(at))
        return { text: "", late: false };
    const w = SHORT[lang === "en" ? "en" : "id"], en = lang === "en";
    const hasTime = String(due).includes("T");
    const time = hasTime ? ` ${pad(at.getHours())}${en ? ":" : "."}${pad(at.getMinutes())}` : "";
    if (at < now)
        return { text: en ? "Late" : "Terlambat", late: true };
    const days = Math.round((day(at) - day(now)) / 864e5);
    if (days === 0)
        return { text: (en ? "Today" : "Hari ini") + time, late: false };
    if (days === 1)
        return { text: (en ? "Tomorrow" : "Besok") + time, late: false };
    const year = at.getFullYear() !== now.getFullYear() ? ` ${at.getFullYear()}` : "";
    return { text: `${w.days[at.getDay()]} ${at.getDate()} ${w.months[at.getMonth()]}${year}${time}`, late: false };
}

// What the due field will save, said back while typing: "→ Jum 7 Nov",
// "tanggal tidak dikenal", or "" while it's empty.
export function duePreview(text, now = new Date(), lang = "id") {
    const p = parseDue(text, now);
    if (!p)
        return lang === "en" ? "date not understood" : "tanggal tidak dikenal";
    return p.due === "" ? "" : "→ " + dueChip(p.due, day(now), lang).text;
}

// ── The calendar picker ────────────────────────────────────────

// Six weeks of a month for a calendar grid, Monday first: { iso, day,
// inMonth, today, past } for each of the 42 days.
export function monthGrid(year, month, now = new Date()) {
    const first = new Date(year, month, 1);
    const start = new Date(year, month, 1 - (first.getDay() + 6) % 7);
    const today = day(now);
    const out = [];
    for (let i = 0; i < 42; i++) {
        const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
        out.push({
            iso: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
            day: d.getDate(),
            inMonth: d.getMonth() === month,
            today: +d === +today,
            past: d < today
        });
    }
    return out;
}

// "November 2026" / "November 2026", and the weekday heads, Monday first.
export function monthTitle(year, month, lang = "id") {
    const names = lang === "en"
        ? ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        : ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];
    return `${names[month]} ${year}`;
}
export function weekHeads(lang = "id") {
    const w = SHORT[lang === "en" ? "en" : "id"].days;
    return w.slice(1).concat(w[0]);
}

// What the due field holds, as the picker needs it: the day ("2026-11-05")
// and the time ("14.00") or "", or null when it's empty or not a date.
export function picked(text, now = new Date()) {
    const p = parseDue(text, now);
    if (!p || p.due === "")
        return null;
    return { iso: p.due.slice(0, 10), time: p.hasTime ? p.due.slice(11, 16).replace(":", ".") : "" };
}

// The due field's text once a day was clicked: "6/11" (with the year when
// it isn't this one), keeping a time already typed.
export function withDay(text, iso, now = new Date()) {
    const [y, m, d] = iso.split("-").map(Number);
    const time = picked(text, now)?.time ?? "";
    const date = y === now.getFullYear() ? `${d}/${m}` : `${d}/${m}/${y}`;
    return time ? `${date} ${time}` : date;
}

// … once a time was clicked ("" takes it away), keeping the day (today
// when there's none yet).
export function withTime(text, time, now = new Date()) {
    const p = picked(text, now);
    const iso = p?.iso ?? `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
    const date = withDay("", iso, now);
    return time ? `${date} ${time}` : date;
}
