// A year of contributions from GitHub's public calendar fragment
// (https://github.com/users/<name>/contributions, no token). Pure, so
// tests/desk-contrib.test.mjs covers it with a saved page.
//
// → {available, user, total, streak, today, busiest, weeks, source}, where
// weeks is one array per week (oldest first) of seven levels 0–4, null
// where the calendar has no day; or {available: false, reason: "user"}.

const CELL = /<td\b[^>]*\bdata-date="(\d{4}-\d{2}-\d{2})"[^>]*\bid="contribution-day-component-(\d+)-(\d+)"[^>]*\bdata-level="(\d)"/g;
const TIP = /<tool-tip\b[^>]*\bfor="contribution-day-component-(\d+)-(\d+)"[^>]*>\s*(No|[\d,]+) contributions? on/g;
const TOTAL = /js-contribution-activity-description[^>]*>\s*([\d,]+)\s+contributions?/;

const num = s => Number(String(s).replace(/,/g, ""));

// Every match of a /g regex (QML's JS engine has no String.matchAll).
function all(re, text) {
    const out = [];
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(text)) !== null)
        out.push(m);
    return out;
}

export function parseContributions(html, user) {
    html = String(html ?? "");
    const cells = all(CELL, html).map(m => ({ date: m[1], row: +m[2], col: +m[3], level: +m[4] }));
    if (cells.length === 0)
        return { available: false, reason: "user" };

    const counts = new Map();
    for (const m of all(TIP, html))
        counts.set(`${m[1]}-${m[2]}`, m[3] === "No" ? 0 : num(m[3]));

    const columns = Math.max(...cells.map(c => c.col)) + 1;
    const weeks = Array.from({ length: columns }, () => Array(7).fill(null));
    for (const c of cells)
        weeks[c.col][c.row] = c.level;

    const days = cells
        .map(c => ({ date: c.date, level: c.level, count: counts.get(`${c.row}-${c.col}`) ?? 0 }))
        .sort((a, b) => a.date.localeCompare(b.date));

    // Like GitHub: today without contributions doesn't end the streak yet.
    let streak = 0;
    for (let i = days.length - 1; i >= 0; i--) {
        if (days[i].level > 0)
            streak++;
        else if (i !== days.length - 1)
            break;
    }

    const total = html.match(TOTAL);
    return {
        available: true,
        user,
        total: total ? num(total[1]) : days.reduce((s, d) => s + d.count, 0),
        streak,
        today: days[days.length - 1].count,
        busiest: Math.max(0, ...days.map(d => d.count)),
        weeks,
        source: `github.com/${user}`
    };
}
