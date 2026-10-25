import { test } from "node:test";
import assert from "node:assert/strict";
import { cookiePoints } from "../integrations/dms/desk/common/cookie.mjs";

const dist = (p, c) => Math.hypot(p.x - c, p.y - c);

test("cookie: a closed outline that stays inside the box", () => {
    const pts = cookiePoints(200, 9, 0.04, 360);
    assert.equal(pts.length, 361);
    assert.ok(Math.abs(pts[0].x - pts[360].x) < 1e-9 && Math.abs(pts[0].y - pts[360].y) < 1e-9);
    for (const p of pts)
        assert.ok(dist(p, 100) <= 100 + 1e-9);
});

test("cookie: `sides` bumps that reach the edge, dips `2 × depth` deep", () => {
    const pts = cookiePoints(200, 9, 0.04, 3600);
    const r = pts.map(p => dist(p, 100));
    assert.ok(Math.abs(Math.max(...r) - 100) < 1e-6);
    assert.ok(Math.abs(Math.min(...r) - (100 - 2 * 8)) < 1e-3);
    // Bumps: local maxima round the outline.
    let bumps = 0;
    for (let i = 0; i < r.length - 1; i++) {
        const prev = r[(i - 1 + r.length - 1) % (r.length - 1)];
        if (r[i] > prev && r[i] >= r[i + 1])
            bumps++;
    }
    assert.equal(bumps, 9);
});
