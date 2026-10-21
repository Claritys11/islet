// The weekly timetable: reading "07.00-08.30" and "Selasa", and which
// lessons fall on a day. Plain functions so Node can test them and QML can
// import them (import "today/timetable.mjs" as Timetable). Times are local.

export const HARI = ["Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu"];
// iCalendar weekday codes, same order as HARI (Date.getDay()).
export const BYDAY = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];

const pad = n => String(n).padStart(2, "0");

function hhmm(h, m) {
    const hh = parseInt(h, 10), mm = parseInt(m, 10);
    return hh <= 23 && mm <= 59 ? `${pad(hh)}:${pad(mm)}` : null;
}

// "07.00-08.30", "07:00 - 08:30", "7.00–8.30", "0700-0830" → { start, end }
export function parseJam(s) {
    const m = String(s ?? "").trim().match(/^(\d{1,2})[.:]?(\d{2})\s*[-–—]\s*(\d{1,2})[.:]?(\d{2})$/);
    if (!m)
        return null;
    const start = hhmm(m[1], m[2]), end = hhmm(m[3], m[4]);
    return start && end && end > start ? { start, end } : null;
}

export function hariIndex(name) {
    const n = String(name ?? "").toLowerCase().replace(/['’\s]/g, "");
    return HARI.findIndex(h => h.toLowerCase() === n);
}

function minutes(t) {
    const [h, m] = t.split(":").map(Number);
    return h * 60 + m;
}

function at(day, time) {
    const d = new Date(day.getFullYear(), day.getMonth(), day.getDate());
    d.setMinutes(minutes(time));
    return d;
}

export function lessonsOn(lessons, date) {
    const day = HARI[date.getDay()];
    return lessons.filter(l => l.hari === day).sort((a, b) => a.start.localeCompare(b.start));
}

// The first lesson of a weekly series: its weekday in the week (Monday to
// Sunday) that `from` falls in, so this week's lessons show too.
export function seriesStart(lesson, from) {
    const monday = new Date(from.getFullYear(), from.getMonth(), from.getDate() - ((from.getDay() + 6) % 7));
    const offset = (hariIndex(lesson.hari) + 6) % 7;
    const day = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + offset);
    return { start: at(day, lesson.start), end: at(day, lesson.end) };
}

// An event's start and end (ISO) as the timetable writes them.
export function fromEvent(startISO, endISO) {
    const s = new Date(startISO), e = new Date(endISO);
    return { hari: HARI[s.getDay()], start: `${pad(s.getHours())}:${pad(s.getMinutes())}`, end: `${pad(e.getHours())}:${pad(e.getMinutes())}` };
}
