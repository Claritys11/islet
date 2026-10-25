// The karaoke fill of one lyric line as keys — [time, fill] points joined by
// straight lines — and the playback clock as an anchor, so whoever draws the
// fill (Islet itself, the DMS bar pill) works it out for any moment without
// being sent the fill 30 times a second. Plain functions; QML's JS engine and
// Node both run them.

// Keys for `line` (as LyricsService keeps it); `sung` is how long a plain
// line takes to sing (the song's pace, worked out by LyricsService).
//   syllables: each fills from its start to its end, held in between
//   a known end: evenly from start to end
//   word times: word by word, full after the last one
//   otherwise: evenly over `sung` seconds (at least 0.1)
export function fillKeys(line, sung) {
    if (!line)
        return [];
    if (line.syl && line.syl.length) {
        const keys = [[line.syl[0].s, 0]];
        for (const x of line.syl) {
            keys.push([x.s, x.from]);
            keys.push([x.e, x.to]);
        }
        return keys;
    }
    if (line.end > line.time)
        return [[line.time, 0], [line.end, 1]];
    if (line.words && line.words.length) {
        const w = line.words;
        const keys = [[w[0].time, 0]];
        for (const x of w)
            keys.push([x.time, x.frac]);
        keys.push([w[w.length - 1].time, 1]);
        return keys;
    }
    return [[line.time, 0], [line.time + Math.max(sung, 0.1), 1]];
}

// The fill (0..1) at time `t`: the last key at or before it, joined to the
// next one; before the first key nothing, after the last its value.
export function fillAt(keys, t) {
    if (!keys.length || t < keys[0][0])
        return 0;
    let i = 0;
    while (i + 1 < keys.length && keys[i + 1][0] <= t)
        i++;
    const [t0, p0] = keys[i];
    if (i + 1 === keys.length)
        return Math.max(0, Math.min(1, p0));
    const [t1, p1] = keys[i + 1];
    const p = p0 + (p1 - p0) * (t - t0) / Math.max(t1 - t0, 0.01);
    return Math.max(0, Math.min(1, p));
}

// The lyric clock `anchor` = { t (seconds), at (ms since epoch), playing,
// rate } read at `now` (ms).
export function clockAt(anchor, now) {
    return anchor.playing ? anchor.t + (now - anchor.at) / 1000 * anchor.rate : anchor.t;
}

// Whether clients need a new anchor: theirs (`sent`) would be off by more
// than 80 ms from `t` now, or it says playing/paused or a rate wrongly.
export function needsAnchor(sent, t, playing, rate, now) {
    if (!sent || sent.playing !== playing || sent.rate !== rate)
        return true;
    return Math.abs(clockAt(sent, now) - t) > 0.08;
}
