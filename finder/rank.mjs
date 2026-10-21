// Finder's ranking and actions: plain functions, no I/O, so Node can test
// them and QML can import them (import "finder/rank.mjs" as Rank).
//
// An entry is { path, kind: "dir" | "file", project: bool }.

const DAY = 864e5;
const WEEK = 7 * DAY;

// fzf's extended search reads a leading ' ! ^ or a trailing $ (and a lone |)
// as operators, and has no escape for them. People type them as plain
// characters, so such a word becomes an exact-match term ('word), which
// matches the rest literally; a trailing $ is dropped (ranking still sees
// the whole query). Spaces separate words that must all match.
export function fzfQuery(q) {
    return q.trim().split(/\s+/).map(w => {
        if (w.length > 1 && w.endsWith("$"))
            w = w.slice(0, -1);
        if (w === "|" || /^['!^]/.test(w) || w === "$")
            return "'" + w;
        return w;
    }).filter(w => w !== "").join(" ");
}

function wordStart(name, i) {
    if (i === 0)
        return true;
    const prev = name[i - 1], cur = name[i];
    return /[\s\-_.()[\]]/.test(prev) || (/[a-z0-9]/.test(prev) && /[A-Z]/.test(cur));
}

// Does the query appear in `name`? Typed words are first tried in order as
// one run of letters ("islet win"); failing that, each word on its own, in
// any order ("windows islet"), for a little less. → { score, positions } or null.
export function nameMatch(q, name) {
    const words = q.trim().split(/\s+/).filter(w => w !== "");
    const whole = matchWord(words.join(""), name);
    if (whole || words.length < 2)
        return whole;
    let score = -5;
    const positions = new Set();
    for (const w of words) {
        const m = matchWord(w, name);
        if (!m)
            return null;
        score += m.score;
        m.positions.forEach(i => positions.add(i));
    }
    return { score, positions: Array.from(positions).sort((a, b) => a - b) };
}

// One word as a subsequence of `name`, letters in order. The best of all
// alignments wins: letters at word starts ("isw" → islet-windows) and runs
// of letters score more.
function matchWord(word, name) {
    const query = word.toLowerCase();
    const lower = name.toLowerCase();
    const n = query.length, m = name.length;
    if (n === 0 || n > m)
        return null;
    // best[i][j]: best score with query[0..i] matched and query[i] at j.
    const best = Array.from({ length: n }, () => new Array(m).fill(-Infinity));
    const from = Array.from({ length: n }, () => new Array(m).fill(-1));
    for (let i = 0; i < n; i++) {
        for (let j = i; j < m; j++) {
            if (lower[j] !== query[i])
                continue;
            const here = 1 + (wordStart(name, j) ? 8 : 0);
            if (i === 0) {
                best[i][j] = here + (j === 0 ? 6 : 0) - 0.1 * j;
                continue;
            }
            for (let k = i - 1; k < j; k++) {
                if (best[i - 1][k] === -Infinity)
                    continue;
                const s = best[i - 1][k] + here + (k === j - 1 ? 5 : -0.2 * (j - k - 1));
                if (s > best[i][j]) {
                    best[i][j] = s;
                    from[i][j] = k;
                }
            }
        }
    }
    let end = -1;
    for (let j = 0; j < m; j++)
        if (best[n - 1][j] > (end < 0 ? -Infinity : best[n - 1][end]))
            end = j;
    if (end < 0 || best[n - 1][end] === -Infinity)
        return null;
    const positions = [];
    for (let i = n - 1, j = end; i >= 0; j = from[i][j], i--)
        positions.unshift(j);
    return { score: best[n - 1][end], positions };
}

// How much you use something: its count, halved for every week since you
// last opened it.
export function frecency(rec, now) {
    if (!rec)
        return 0;
    return rec.count * Math.pow(0.5, (now - rec.last) / WEEK);
}

function baseName(path) {
    return path.replace(/\/+$/, "").split("/").pop() || path;
}

// Entries fzf matched, best first. A name match beats a match only somewhere
// in the path; projects, folders and things you open often rise.
export function rank(q, entries, history, now) {
    const scored = entries.map((e, order) => {
        const m = nameMatch(q, baseName(e.path));
        const depth = e.path.split("/").length;
        const score = (m ? m.score : -30) + (e.project ? 40 : 0) + 15 * Math.min(frecency(history[e.path], now), 10) + (e.kind === "dir" ? 10 : 0) - 0.02 * depth;
        return Object.assign({}, e, { score, positions: m ? m.positions : [], order });
    });
    // Stable: equal scores keep fzf's order.
    scored.sort((a, b) => b.score - a.score || a.order - b.order);
    for (const e of scored)
        delete e.order;
    return scored;
}

export function recent(history, now, limit = 8) {
    return Object.entries(history)
        .map(([path, rec]) => ({ path, kind: rec.kind ?? "file", f: frecency(rec, now) }))
        .sort((a, b) => b.f - a.f)
        .slice(0, limit)
        .map(({ path, kind }) => ({ path, kind }));
}

// Opened `entry`: a new history object (QML var properties need a new value
// to notice a change), keeping the 500 most used.
export function remember(history, entry, now) {
    const next = Object.assign({}, history);
    const old = next[entry.path];
    next[entry.path] = { count: (old ? old.count : 0) + 1, last: now, kind: entry.kind };
    const keys = Object.keys(next);
    if (keys.length > 500) {
        keys.sort((a, b) => frecency(next[a], now) - frecency(next[b], now));
        for (const k of keys.slice(0, keys.length - 500))
            delete next[k];
    }
    return next;
}

export function shortPath(path, home) {
    if (path === home)
        return "~";
    return home && path.startsWith(home + "/") ? "~" + path.slice(home.length) : path;
}

export function detect(candidates, available) {
    return candidates.find(c => available.includes(c)) ?? "";
}

function dirName(path) {
    const i = path.replace(/\/+$/, "").lastIndexOf("/");
    return i > 0 ? path.slice(0, i) : "/";
}

// The command for an action, as argv (never a shell string, so any path is
// one argument). apps: { fileManager, terminal, editor }, already resolved.
export function actionCommand(action, entry, apps) {
    const path = entry.path;
    const folder = entry.kind === "dir" ? path : dirName(path);
    const fm = apps.fileManager || "";
    switch (action) {
    case "terminal": {
        const t = apps.terminal;
        const name = t.split("/").pop();
        // A running Ghostty would open the window itself, in the folder of
        // the terminal in focus: its own process honours the folder.
        if (name === "ghostty")
            return [t, "--gtk-single-instance=false", `--working-directory=${folder}`];
        if (name === "foot")
            return [t, `--working-directory=${folder}`];
        if (name === "kitty")
            return [t, "--directory", folder];
        if (name === "alacritty")
            return [t, "--working-directory", folder];
        if (name === "konsole")
            return [t, "--workdir", folder];
        return ["sh", "-c", 'cd "$1" && exec "$0"', t, folder];
    }
    case "editor":
        return [apps.editor, path];
    case "reveal":
        if (fm.split("/").pop() === "dolphin")
            return [fm, "--select", path];
        return [fm || "xdg-open", dirName(path)];
    case "copy":
        return ["wl-copy", "--", path];
    default:
        // Folders go to the chosen file manager, files to their own app.
        return [entry.kind === "dir" && fm ? fm : "xdg-open", path];
    }
}
