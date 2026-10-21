// Deadlines for the Today tab: what's due soon, in plain words, and which
// things overlap. Plain functions; times are local.

const SHORT = ["Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"];
const pad = n => String(n).padStart(2, "0");

function startOfDay(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function daysBetween(a, b) {
    return Math.round((startOfDay(b) - startOfDay(a)) / 864e5);
}

// A date-only due date means "by the end of that day".
export function dueDate(value) {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
    return m ? new Date(+m[1], +m[2] - 1, +m[3], 23, 59, 59) : new Date(value);
}

// "hari ini 23.59", "besok", "Jum, 2 hari", "terlambat 1 hari"
export function label(due, hasTime, now) {
    const time = hasTime ? ` ${pad(due.getHours())}.${pad(due.getMinutes())}` : "";
    const days = daysBetween(now, due);
    if (due < now) {
        if (days < 0)
            return `terlambat ${-days} hari`;
        const mins = Math.round((now - due) / 60000);
        return mins < 60 ? `terlambat ${mins} mnt` : `terlambat ${Math.round(mins / 60)} jam`;
    }
    if (days === 0)
        return `hari ini${time}`;
    if (days === 1)
        return `besok${time}`;
    return `${SHORT[due.getDay()]}, ${days} hari`;
}

function urgency(due, now) {
    if (due < now)
        return "overdue";
    const days = daysBetween(now, due);
    return days === 0 ? "today" : days === 1 ? "tomorrow" : "later";
}

// Unfinished Notion tasks and Classroom assignments due by the end of
// `days` days from today (overdue ones included), soonest first.
export function dueSoon(tasks, classroom, now, days) {
    const until = new Date(now.getFullYear(), now.getMonth(), now.getDate() + days + 1);
    const out = [];
    for (const t of tasks) {
        if (t.done || !t.due)
            continue;
        out.push({ key: `notion:${t.pageId}`, title: t.title, source: "notion", pageId: t.pageId, due: dueDate(t.due), hasTime: t.dueHasTime, priority: t.priority ?? "" });
    }
    for (const e of classroom) {
        const due = e.allDay ? dueDate(String(e.start).slice(0, 10)) : new Date(e.start);
        out.push({ key: `classroom:${e.id}`, title: e.title, source: "classroom", due, hasTime: !e.allDay, priority: "" });
    }
    return out.filter(d => d.due < until).sort((a, b) => a.due - b.due).map(d => Object.assign(d, { label: label(d.due, d.hasTime, now), urgency: urgency(d.due, now) }));
}

// Keys of items whose time overlaps another's (back-to-back isn't a clash).
export function clashes(items) {
    const out = new Set();
    for (let i = 0; i < items.length; i++)
        for (let j = i + 1; j < items.length; j++)
            if (items[i].start < items[j].end && items[j].start < items[i].end) {
                out.add(items[i].key);
                out.add(items[j].key);
            }
    return out;
}
