// The formatting shortcuts (Notion's) and toolbar buttons shared by the
// Notes widget and the patched DMS notepad. Pure, so `node --test tests/`
// covers it; FormatBar.qml turns an action into an mdedit.mjs call.

export const TOOLS = [
    { id: "bold", label: "B", tip: "Tebal · Ctrl+B" },
    { id: "italic", label: "I", tip: "Miring · Ctrl+I" },
    { id: "underline", label: "U", tip: "Garis bawah · Ctrl+U" },
    { id: "strike", label: "S", tip: "Coret · Ctrl+Shift+S" },
    { id: "code", label: "</>", tip: "Kode · Ctrl+E" },
    { id: "link", label: "🔗", tip: "Link · Ctrl+K" },
    { id: "h1", label: "H1", tip: "Judul 1 · Ctrl+Shift+1" },
    { id: "h2", label: "H2", tip: "Judul 2 · Ctrl+Shift+2" },
    { id: "h3", label: "H3", tip: "Judul 3 · Ctrl+Shift+3" },
    { id: "todo", label: "☐", tip: "To-do · Ctrl+Shift+4" },
    { id: "bullet", label: "•", tip: "Bullet · Ctrl+Shift+5" },
    { id: "number", label: "1.", tip: "Bernomor · Ctrl+Shift+6" },
    { id: "quote", label: "❝", tip: "Kutipan · Ctrl+Shift+." }
];

// Qt's key codes for these are their ASCII codes. With Shift, a digit can
// arrive as itself or as its shifted symbol, depending on the layout.
const CTRL = { B: "bold", I: "italic", U: "underline", E: "code", K: "link" };
const CTRL_SHIFT = {
    "1": "h1", "!": "h1", "2": "h2", "@": "h2", "3": "h3", "#": "h3",
    "4": "todo", "$": "todo", "5": "bullet", "%": "bullet", "6": "number", "^": "number",
    ".": "quote", ">": "quote", S: "strike"
};

// The toolbar action for a key press, or null when it isn't one.
export function keyAction(key, ctrl, shift) {
    if (!ctrl || key > 0x7f)
        return null;
    const c = String.fromCharCode(key);
    return (shift ? CTRL_SHIFT[c] : CTRL[c]) ?? null;
}
