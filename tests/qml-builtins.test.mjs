import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, lstatSync } from "node:fs";
import { join, relative } from "node:path";

// QML's JavaScript engine (V4, Qt 6.12) lacks these, checked in a running
// Quickshell; Node has them, so other tests can't catch a use. Each
// worked once in the tests and failed in Islet or DMS ("Property 'trimEnd'
// of object is not a function").
const MISSING = /\.(trimEnd|trimStart|trimLeft|trimRight|replaceAll|matchAll|at|flat|flatMap|findLast|findLastIndex)\(|Object\.fromEntries\(|structuredClone\(/;

const root = new URL("..", import.meta.url).pathname;
function files(dir, out = []) {
    for (const name of readdirSync(dir)) {
        if ([".git", "node_modules", "tests", "docs", ".superpowers", "tools", "spicetify"].includes(name))
            continue;
        const p = join(dir, name);
        // Symlinks (each plugin's common/, fill.mjs) are the same files again.
        const st = lstatSync(p);
        if (st.isSymbolicLink())
            continue;
        if (st.isDirectory())
            files(p, out);
        else if (/\.(qml|mjs|js)$/.test(name))
            out.push(p);
    }
    return out;
}
// Strings and comments say anything (a Notion formula uses .at()).
const code = line => line.replace(/\/\/.*$/, "").replace(/'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"/g, "\"\"");

test("no built-in that QML's JavaScript lacks is used", () => {
    const found = [];
    for (const f of files(root))
        readFileSync(f, "utf8").split("\n").forEach((line, i) => {
            if (MISSING.test(code(line)))
                found.push(`${relative(root, f)}:${i + 1}: ${line.trim()}`);
        });
    assert.deepEqual(found, []);
});
