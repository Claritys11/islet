import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { parseContributions } from "../integrations/dms/desk/github/contrib.mjs";

const html = readFileSync(new URL("./fixtures/github-contributions.html", import.meta.url), "utf8");

test("a real contributions page: the numbers the old scraper gave", () => {
    const r = parseContributions(html, "Claritys11");
    assert.equal(r.available, true);
    assert.equal(r.user, "Claritys11");
    assert.equal(r.total, 766);
    assert.equal(r.streak, 42);
    assert.equal(r.today, 0);
    assert.equal(r.busiest, 47);
    assert.equal(r.weeks.length, 53);
    assert.equal(r.weeks.flat().filter(d => d === null).length, 6);
    assert.deepEqual(r.weeks[52], [0, null, null, null, null, null, null]);
    assert.equal(r.source, "github.com/Claritys11");
});

test("no calendar (wrong name or private): unavailable, reason user", () => {
    assert.deepEqual(parseContributions("<html>Not Found</html>", "nobody"), { available: false, reason: "user" });
});

test("streak: an empty today doesn't end it, an earlier gap does", () => {
    const cell = (d, row, col, level) => `<td data-date="2026-01-0${d}" id="contribution-day-component-${row}-${col}" data-level="${level}">`;
    const page = [cell(1, 0, 0, 1), cell(2, 1, 0, 0), cell(3, 2, 0, 2), cell(4, 3, 0, 1), cell(5, 4, 0, 0)].join("\n");
    assert.equal(parseContributions(page, "x").streak, 2);
});

test("works without String.prototype.matchAll (QML's V4 engine lacks it)", () => {
    const saved = String.prototype.matchAll;
    delete String.prototype.matchAll;
    try {
        assert.equal(parseContributions(html, "Claritys11").total, 766);
    } finally {
        String.prototype.matchAll = saved;
    }
});
