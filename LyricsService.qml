pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Follows an MPRIS player, fetches lyrics from LRCLIB and tracks the
// currently sung line and how far into it the singer is.
Singleton {
    id: root

    readonly property MprisPlayer player: {
        const players = Mpris.players.values;
        const want = Config.opts.player.toLowerCase();
        if (want === "")
            return players.find(p => p.isPlaying) ?? players[0] ?? null;
        return players.find(p => [p.identity, p.desktopEntry, p.dbusName].some(s => (s ?? "").toLowerCase().includes(want))) ?? null;
    }

    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""
    readonly property bool isPlaying: player?.isPlaying ?? false

    // "idle" | "loading" | "ready" | "notfound" | "error"
    property string status: "idle"
    // Sorted by time. Each line:
    //   { time, text, main, bg, bgOnly, interlude, words: [{ time, frac }] | null }
    property var lines: []
    property bool synced: false

    // Playback clock in seconds, interpolated between MPRIS polls so the
    // karaoke fill moves smoothly instead of in 100 ms steps.
    property real position: 0
    property real _basePos: 0
    property real _baseAt: 0
    readonly property real time: position + Config.opts.offsetMs / 1000

    readonly property int currentIndex: {
        const n = lines.length;
        if (n === 0)
            return 0;
        if (!synced) {
            const len = player?.length ?? 0;
            return len > 0 ? Math.min(n - 1, Math.max(0, Math.floor(time / len * n))) : 0;
        }
        // Binary search for the last line whose timestamp has passed.
        let lo = 0, hi = n - 1;
        while (lo < hi) {
            const mid = (lo + hi + 1) >> 1;
            if (lines[mid].time <= time)
                lo = mid;
            else
                hi = mid - 1;
        }
        return lo;
    }

    // 0 → 1: how much of the current line has been sung.
    readonly property real progress: synced ? lineProgress(currentIndex, time) : 1

    function lineProgress(i, t) {
        const l = lines[i];
        if (!l)
            return 0;
        if (l.words) {
            const w = l.words;
            if (t <= w[0].time)
                return 0;
            for (let k = 0; k < w.length - 1; k++) {
                if (t < w[k + 1].time)
                    return w[k].frac + (w[k + 1].frac - w[k].frac) * (t - w[k].time) / Math.max(w[k + 1].time - w[k].time, 0.01);
            }
            return 1;
        }
        const next = lines[i + 1]?.time ?? (player?.length > 0 ? player.length : l.time + 5);
        // Without word timings, assume the line is sung at a natural pace and
        // then held, rather than stretched across a long instrumental gap.
        const dur = l.interlude ? next - l.time : Math.min(next - l.time, 0.8 + l.text.length * 0.12);
        return Math.max(0, Math.min(1, (t - l.time) / Math.max(dur, 0.1)));
    }

    function seek(index) {
        if (!player?.canSeek || !synced || !lines[index])
            return;
        player.position = Math.max(0, lines[index].time - Config.opts.offsetMs / 1000 + 0.05);
        resync(player.position);
    }

    function refetch() {
        delete _cache[trackKey];
        fetchLyrics();
    }

    function resync(pos) {
        _basePos = pos;
        _baseAt = Date.now();
        position = pos;
    }

    // ── Clock ─────────────────────────────────────────────────────
    // MPRIS position isn't pushed continuously, so poll it and extrapolate.
    Timer {
        running: root.player !== null
        repeat: true
        interval: 250
        onTriggered: {
            root.player.positionChanged();
            const reported = root.player.position;
            // Small disagreements are poll jitter; only resync on real jumps
            // (seeks, pauses) so the clock never stutters backwards.
            if (!root.isPlaying || Math.abs(reported - root.position) > 0.3)
                root.resync(reported);
        }
    }

    FrameAnimation {
        running: root.isPlaying
        onTriggered: root.position = root._basePos + (Date.now() - root._baseAt) / 1000
    }

    onIsPlayingChanged: if (player)
        resync(player.position)

    // ── Track changes ─────────────────────────────────────────────
    readonly property string trackKey: title === "" ? "" : `${artist}\n${title}`
    onTrackKeyChanged: {
        lines = [];
        status = trackKey === "" ? "idle" : "loading";
        // Metadata often arrives in pieces; wait for it to settle.
        fetchDebounce.restart();
    }

    Timer {
        id: fetchDebounce
        interval: 400
        onTriggered: root.fetchLyrics()
    }

    property var _cache: ({})
    property int _requestId: 0

    function fetchLyrics() {
        const key = trackKey;
        if (key === "")
            return;
        if (_cache[key]) {
            apply(_cache[key]);
            return;
        }
        status = "loading";
        const id = ++_requestId;
        const api = Config.opts.lrclibUrl;
        const duration = player?.length ?? 0;
        const base = `artist_name=${encodeURIComponent(artist)}&track_name=${encodeURIComponent(title)}`;
        const exact = `${api}/api/get?${base}` + (duration > 0 ? `&duration=${Math.round(duration)}` : "");

        request(exact, (ok, data) => {
            if (id !== _requestId)
                return;
            if (ok && hasLyrics(data))
                return finish(key, data);
            // Fall back to a fuzzy search with a cleaned-up title
            // ("Song - Remastered 2011" → "Song").
            const q = `artist_name=${encodeURIComponent(artist)}&track_name=${encodeURIComponent(cleanTitle(title))}`;
            request(`${api}/api/search?${q}`, (ok2, results) => {
                if (id !== _requestId)
                    return;
                if (!ok2) {
                    status = "error";
                    return;
                }
                finish(key, pickBest(results ?? [], duration));
            });
        });
    }

    function finish(key, data) {
        const parsed = data ? parse(data) : null;
        if (parsed)
            _cache[key] = parsed;
        apply(parsed);
    }

    function apply(parsed) {
        if (!parsed) {
            lines = [];
            synced = false;
            status = "notfound";
            return;
        }
        synced = parsed.synced;
        lines = parsed.lines;
        status = "ready";
    }

    function hasLyrics(d) {
        return d && (d.instrumental || d.syncedLyrics || d.plainLyrics);
    }

    function pickBest(results, duration) {
        const usable = results.filter(hasLyrics);
        const score = r => (r.syncedLyrics ? 0 : 1000) + (duration > 0 ? Math.abs((r.duration ?? 0) - duration) : 0);
        usable.sort((a, b) => score(a) - score(b));
        return usable[0] ?? null;
    }

    function cleanTitle(t) {
        return t.replace(/\s+-\s+.*$/, "").replace(/\s*[(\[](feat|ft|with)\.?\s[^)\]]*[)\]]/i, "").trim();
    }

    // ── Parsing ───────────────────────────────────────────────────
    readonly property string interludeText: "•  •  •"

    // Split "I want you (want you)" into the lead vocal and the background
    // vocal so they can be styled separately.
    function makeLine(time, text, words) {
        const groups = text.match(/\([^)]*\)/g) ?? [];
        const main = text.replace(/\s*\([^)]*\)\s*/g, " ").replace(/\s+/g, " ").trim();
        const bg = groups.map(g => g.slice(1, -1).trim()).filter(g => g !== "").join("  ");
        return {
            time,
            text,
            main: main || bg,
            bg: main ? bg : "",
            bgOnly: main === "" && bg !== "",
            interlude: text === interludeText,
            words
        };
    }

    // Enhanced LRC: "<00:12.34>word <00:12.80>word" → [{ time, frac }], where
    // frac is how far through the line's characters each word starts.
    function parseWords(body) {
        const tag = /<(\d+):(\d+(?:\.\d+)?)>/g;
        if (!tag.test(body))
            return { text: body.trim(), words: null };
        tag.lastIndex = 0;
        const marks = [];
        let text = "", last = 0, m;
        while ((m = tag.exec(body)) !== null) {
            text += body.slice(last, m.index);
            marks.push({ time: parseInt(m[1]) * 60 + parseFloat(m[2]), at: text.length });
            last = tag.lastIndex;
        }
        text += body.slice(last);
        const len = Math.max(text.trimEnd().length, 1);
        const words = marks.map(k => ({ time: k.time, frac: Math.min(1, k.at / len) }));
        if (words[words.length - 1].frac < 1)
            words.push({ time: words[words.length - 1].time + 0.4, frac: 1 });
        return { text: text.trim(), words };
    }

    function parse(d) {
        if (d.instrumental)
            return { synced: false, lines: [makeLine(0, "♪  Instrumental  ♪", null)] };
        if (d.syncedLyrics) {
            const out = [];
            const tag = /\[(\d+):(\d+(?:\.\d+)?)\]/g;
            for (const raw of d.syncedLyrics.split("\n")) {
                const { text, words } = parseWords(raw.replace(tag, ""));
                let m;
                tag.lastIndex = 0;
                // A line may carry several timestamps ([00:12.00][01:30.00] chorus).
                while ((m = tag.exec(raw)) !== null)
                    out.push(makeLine(parseInt(m[1]) * 60 + parseFloat(m[2]), text || interludeText, words));
            }
            out.sort((a, b) => a.time - b.time);
            if (out.length === 0)
                return null;
            if (out[0].time > 0.5)
                out.unshift(makeLine(0, interludeText, null));
            return { synced: true, lines: out };
        }
        const plain = d.plainLyrics.split("\n").map(s => s.trim()).filter(s => s !== "");
        return plain.length ? { synced: false, lines: plain.map(text => makeLine(0, text, null)) } : null;
    }

    function request(url, cb) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status === 200) {
                try {
                    cb(true, JSON.parse(xhr.responseText));
                } catch (e) {
                    cb(false, null);
                }
            } else {
                cb(false, null);
            }
        };
        xhr.open("GET", url);
        xhr.setRequestHeader("Lrclib-Client", "lyrics-wheel (https://github.com/Claritys11/lyrics-wheel)");
        xhr.send();
    }
}
