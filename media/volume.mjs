// Per-app volume for the playing player: steps on a 5% grid, and the
// PipeWire stream that belongs to a player whose MPRIS can't set volume.

// `v` (0–1) moved by `steps` of 5%, snapped onto the grid.
export function nudge(v, steps) {
    const x = v * 20, r = Math.round(x);
    const at = Math.abs(x - r) < 1e-3 ? r : steps > 0 ? Math.floor(x) : Math.ceil(x);
    return Math.min(20, Math.max(0, at + steps)) / 20;
}

const norm = s => String(s ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");

// Every stream of the player's app (an app may have more than one).
// streams: [{ id, app, binary, media }] (application.name,
// application.process.binary, media.name); player: { identity,
// desktopEntry }. Exact names first, else one name inside the other.
export function pickStreams(streams, player) {
    if (!player)
        return [];
    const want = [player.identity, player.desktopEntry].map(norm).filter(s => s.length >= 3);
    const names = s => [s.app, s.binary, s.media].map(norm).filter(x => x.length >= 3);
    const exact = streams.filter(s => names(s).some(n => want.includes(n)));
    return exact.length ? exact : streams.filter(s => names(s).some(n => want.some(w => n.includes(w) || w.includes(n))));
}
