import { test } from "node:test";
import assert from "node:assert/strict";
import { cacheName } from "../media/art.mjs";

test("cacheName: web art gets a stable file name of its own", () => {
    const a = cacheName("https://i.scdn.co/image/ab67616d0000b273c607bcd8");
    assert.match(a, /^[0-9a-f]{8,}\.img$/);
    assert.equal(cacheName("https://i.scdn.co/image/ab67616d0000b273c607bcd8"), a);
    assert.notEqual(cacheName("https://i.scdn.co/image/ab67616d0000b273c607bcd9"), a);
    assert.match(cacheName("http://example.com/x.png"), /\.img$/);
});

test("cacheName: local or missing art needs no download", () => {
    assert.equal(cacheName("file:///tmp/cover.jpg"), null);
    assert.equal(cacheName("qrc:/demo.jpg"), null);
    assert.equal(cacheName(""), null);
    assert.equal(cacheName(undefined), null);
});
