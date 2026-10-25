// The Notes widget's editor: the text operations behind its toolbar and
// shortcuts, on (text, selectionStart, selectionEnd). Each returns the new
// text and selection {text, start, end}; NotesWidget applies it with
// diff() so the editor's undo keeps working. Pure, so `node --test tests/`
// covers it.

const result = (text, start, end = start) => ({ text, start, end });

// **bold**, *italic*, ~~strike~~, <u>underline</u>, `code`: on, or off when
// the selection is already wrapped (inside or including the markers).
export function wrap(text, s, e, open, close = open) {
    const sel = text.slice(s, e);
    if (text.slice(s - open.length, s) === open && text.slice(e, e + close.length) === close)
        return result(text.slice(0, s - open.length) + sel + text.slice(e + close.length), s - open.length, e - open.length);
    if (sel.length >= open.length + close.length && sel.startsWith(open) && sel.endsWith(close)) {
        const inner = sel.slice(open.length, sel.length - close.length);
        return result(text.slice(0, s) + inner + text.slice(e), s, s + inner.length);
    }
    return result(text.slice(0, s) + open + sel + close + text.slice(e), s + open.length, e + open.length);
}

// The lines a selection touches: [first line start, last line end].
function lineSpan(text, s, e) {
    const from = text.lastIndexOf("\n", s - 1) + 1;
    let to = text.indexOf("\n", Math.max(e - (e > s && text[e - 1] === "\n" ? 1 : 0), s));
    if (to < 0)
        to = text.length;
    return [from, to];
}

const PREFIX = /^(#{1,3} |- \[[ xX]\] |\[[ xX]\] |[-*] |\d+[.)] |> )/;
const KIND = { h1: "# ", h2: "## ", h3: "### ", bullet: "- ", todo: "- [ ] ", quote: "> " };

function kindOf(body) {
    const m = body.match(PREFIX);
    if (!m)
        return null;
    const p = m[1];
    if (p.startsWith("#"))
        return ["h1", "h2", "h3"][p.length - 2];
    if (p.includes("["))
        return "todo";
    if (/^\d/.test(p))
        return "number";
    return p === "> " ? "quote" : "bullet";
}

// Heading 1–3, bullet, number, todo or quote for every line the selection
// touches; off again when they all already are that kind.
export function setBlock(text, s, e, kind) {
    const [from, to] = lineSpan(text, s, e);
    const lines = text.slice(from, to).split("\n");
    const parts = lines.map(l => {
        const indent = l.match(/^[ \t]*/)[0];
        const body = l.slice(indent.length);
        const m = body.match(PREFIX);
        return { indent, kind: kindOf(body), rest: m ? body.slice(m[1].length) : body };
    });
    const off = parts.every(p => p.kind === kind);
    let n = 0;
    const out = parts.map(p => p.indent + (off ? "" : kind === "number" ? `${++n}. ` : KIND[kind]) + p.rest).join("\n");
    const text2 = text.slice(0, from) + out + text.slice(to);
    // One line: keep the cursor where it was in the text; several: select them.
    if (lines.length === 1) {
        const shift = out.length - (to - from);
        return result(text2, Math.max(from, s + shift), Math.max(from, e + shift));
    }
    return result(text2, from, from + out.length);
}

// [text](https://): the URL selected, ready to be typed over; with nothing
// selected the word "teks" is selected instead.
export function link(text, s, e) {
    const sel = text.slice(s, e);
    if (sel === "") {
        const ins = "[teks](https://)";
        return result(text.slice(0, s) + ins + text.slice(e), s + 1, s + 5);
    }
    const ins = `[${sel}](https://)`;
    const at = s + sel.length + 3;
    return result(text.slice(0, s) + ins + text.slice(e), at, at + 8);
}

// Enter at the end of a list line: the next item, numbered on; Enter on an
// empty item ends the list. null when the editor should just break the line.
export function onEnter(text, pos) {
    const from = text.lastIndexOf("\n", pos - 1) + 1;
    let to = text.indexOf("\n", pos);
    if (to < 0)
        to = text.length;
    if (pos !== to)
        return null;
    const line = text.slice(from, to);
    const m = line.match(/^([ \t]*)(- \[[ xX]\] |[-*] |(\d+)([.)]) |> )(.*)$/);
    if (!m)
        return null;
    if (m[5].trim() === "")
        return result(text.slice(0, from) + text.slice(to), from);
    const next = m[3] !== undefined ? `${Number(m[3]) + 1}${m[4]} ` : m[2].startsWith("- [") ? "- [ ] " : m[2];
    const ins = "\n" + m[1] + next;
    return result(text.slice(0, pos) + ins + text.slice(pos), pos + ins.length);
}

// Tab / Shift+Tab: two spaces more or less on every line the selection
// touches, so sub-lists are typed the way NotesService nests them.
export function indent(text, s, e, dir) {
    const [from, to] = lineSpan(text, s, e);
    const lines = text.slice(from, to).split("\n");
    let first = 0, total = 0;
    const out = lines.map((l, i) => {
        let d;
        if (dir > 0) {
            d = 2;
            l = "  " + l;
        } else {
            d = -Math.min(2, l.match(/^ */)[0].length);
            l = l.slice(-d);
        }
        if (i === 0)
            first = d;
        total += d;
        return l;
    }).join("\n");
    const text2 = text.slice(0, from) + out + text.slice(to);
    if (lines.length === 1)
        return result(text2, Math.max(from, s + first), Math.max(from, e + first));
    return result(text2, from, to + total);
}

// The one replace that turns `a` into `b`: TextEdit.remove(at, at + remove)
// then insert(at, insert).
export function diff(a, b) {
    let at = 0;
    while (at < a.length && at < b.length && a[at] === b[at])
        at++;
    let ea = a.length, eb = b.length;
    while (ea > at && eb > at && a[ea - 1] === b[eb - 1]) {
        ea--;
        eb--;
    }
    return { at, remove: ea - at, insert: b.slice(at, eb) };
}

// A draft's name in the tab row: its first line without Markdown.
export function draftTitle(text) {
    const line = String(text ?? "").split("\n").find(l => l.trim() !== "") ?? "";
    const plain = line.trim()
        .replace(PREFIX, "")
        .replace(/\*\*|~~|<\/?u>|`|\*/g, "")
        .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
        .trim();
    return plain.length > 28 ? plain.slice(0, 27) + "…" : plain;
}
