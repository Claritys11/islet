// The clock's "cookie": a circle whose edge rises and falls `sides` times.
// Pure, so tests/desk-cookie.test.mjs covers it.
//
// size: the square it fills; depth: how far each dip goes in, as a part
// of the size (both directions, so the shape spans size exactly);
// steps: points round the outline (the last repeats the first).
export function cookiePoints(size, sides, depth, steps) {
    const c = size / 2;
    const swing = depth * size;
    const base = c - swing;
    const points = [];
    for (let i = 0; i <= steps; i++) {
        const t = (2 * Math.PI * i) / steps;
        // cos: one bump sits on the x axis (at 3 o'clock).
        const r = base + swing * Math.cos(sides * t);
        points.push({ x: c + r * Math.cos(t), y: c + r * Math.sin(t) });
    }
    return points;
}
