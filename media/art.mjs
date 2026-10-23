// Album art from the web, kept as local files so the DankMaterialShell bar
// widget never loads anything over https itself.

// FNV-1a, twice with different seeds: 16 hex digits, stable across runs.
function hash(s, seed) {
    let h = seed >>> 0;
    for (let i = 0; i < s.length; i++) {
        h ^= s.charCodeAt(i);
        h = Math.imul(h, 16777619) >>> 0;
    }
    return h.toString(16).padStart(8, "0");
}

// The cache file name for web art; null when it's already local (or none).
export function cacheName(url) {
    const u = String(url ?? "");
    if (!/^https?:\/\//i.test(u))
        return null;
    return `${hash(u, 2166136261)}${hash(u, 33554467)}.img`;
}
