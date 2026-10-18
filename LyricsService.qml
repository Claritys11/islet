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

    // Sample lyrics so settings can be previewed without music playing.
    property bool demo: false

    readonly property string title: demo ? "Sample Song" : player?.trackTitle ?? ""
    readonly property string artist: demo ? "Islet preview" : player?.trackArtist ?? ""
    readonly property real length: demo ? demoLength : player?.length ?? 0
    readonly property bool isPlaying: demo || (player?.isPlaying ?? false)
    readonly property bool hasTrack: title !== ""

    // "idle" | "loading" | "ready" | "notfound" | "error"
    property string status: "idle"
    // Sorted by time. Each line:
    //   { time, text, main, bg, bgOnly, interlude, words: [{ time, frac }] | null }
    property var lines: []
    property bool synced: false
    // The chosen lyrics are for a recording of a different length, so the
    // timing may not match (e.g. a live or radio version).
    property bool timingMismatch: false
    // Other LRCLIB versions of this song: [{ id, label, duration, synced }]
    property var candidates: []
    property int chosenId: 0

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
        if (!synced)
            return length > 0 ? Math.min(n - 1, Math.max(0, Math.floor(time / length * n))) : 0;
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

    function nextTime(i) {
        return lines[i + 1]?.time ?? (length > 0 ? length : (lines[i]?.time ?? 0) + 5);
    }

    // Without word timings, assume a line is sung at a natural pace and then
    // held, rather than stretched across a long instrumental gap.
    function mainDuration(i) {
        const l = lines[i];
        const gap = nextTime(i) - l.time;
        return l.interlude ? gap : Math.min(gap, 0.8 + l.main.length * 0.12);
    }

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
        return Math.max(0, Math.min(1, (t - l.time) / Math.max(mainDuration(i), 0.1)));
    }

    // Background vocals usually answer the lead ("I want you (want you)") and
    // spill into the next line, so they get their own window: starting
    // part-way through the main phrase and glowing until they've been sung,
    // even after the wheel has moved on.
    //   → { progress: 0..1, glow: 0..1 }
    function bgState(i, t) {
        const l = lines[i];
        if (!synced || !l || l.bg === "")
            return { progress: 0, glow: 0 };
        const main = mainDuration(i);
        const start = l.time + main * 0.55;
        const sung = 0.6 + l.bg.length * 0.13;
        const end = start + sung;
        const hold = Config.opts.bgLinger;
        const progress = Math.max(0, Math.min(1, (t - start) / sung));
        const glow = t < l.time ? 0 : t < end ? 1 : Math.max(0, 1 - (t - end) / Math.max(hold, 0.01));
        return { progress, glow };
    }

    function seek(index) {
        if (demo || !player?.canSeek || !synced || !lines[index])
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
        running: root.player !== null && !root.demo
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
        onTriggered: {
            const t = root._basePos + (Date.now() - root._baseAt) / 1000;
            root.position = root.demo ? t % root.demoLength : t;
        }
    }

    onIsPlayingChanged: if (player && !demo)
        resync(player.position)

    onDemoChanged: {
        if (demo) {
            _requestId++;
            apply(parse({ syncedLyrics: demoLrc }));
            resync(0);
        } else {
            lines = [];
            fetchDebounce.restart();
            if (player)
                resync(player.position);
        }
    }

    // ── Track changes ─────────────────────────────────────────────
    readonly property string trackKey: demo || title === "" ? "" : `${artist}\n${title}`
    onTrackKeyChanged: {
        if (demo)
            return;
        lines = [];
        candidates = [];
        chosenId = 0;
        status = trackKey === "" ? "idle" : "loading";
        retry.attempt = 0;
        retry.stop();
        _lengthWaits = 0;
        // Metadata often arrives in pieces; wait for it to settle.
        fetchDebounce.restart();
    }

    Timer {
        id: fetchDebounce
        interval: 400
        onTriggered: root.fetchLyrics()
    }

    // LRCLIB is a free community server and is sometimes busy: retry with
    // growing gaps instead of giving up on the song.
    Timer {
        id: retry
        property int attempt: 0
        interval: Math.min(60000, 4000 * Math.pow(2, attempt))
        onTriggered: {
            attempt++;
            root.fetchLyrics();
        }
    }

    property var _cache: ({})
    property int _lengthWaits: 0
    property int _requestId: 0

    function fetchLyrics() {
        const key = trackKey;
        if (key === "")
            return;
        if (_cache[key]) {
            apply(_cache[key]);
            return;
        }
        // Spotify sometimes reports the length a moment after the title.
        // Without it we can't tell album, live and radio versions apart, so
        // give it a few seconds.
        if (length <= 0 && _lengthWaits < 8) {
            _lengthWaits++;
            fetchDebounce.restart();
            return;
        }
        status = "loading";
        const id = ++_requestId;
        const api = Config.opts.lrclibUrl;
        const override = Store.db.lyricsChoice?.[key];
        const base = `artist_name=${encodeURIComponent(artist)}&track_name=${encodeURIComponent(title)}`;
        const exact = override ? `${api}/api/get/${override}` : `${api}/api/get?${base}` + (length > 0 ? `&duration=${Math.round(length)}` : "");

        request(exact, (code, data) => {
            if (id !== _requestId)
                return;
            if (code === 200 && hasLyrics(data))
                return finish(key, data);
            // Server trouble: try again later rather than settling for a
            // fuzzy match that may be a different recording.
            if (code !== 404 && code !== 200)
                return failed();
            searchVersions(key, id, true);
        });
    }

    // Look up every LRCLIB version of this song. With `pick`, use the best.
    function searchVersions(key, id, pick) {
        const q = `artist_name=${encodeURIComponent(artist)}&track_name=${encodeURIComponent(cleanTitle(title))}`;
        request(`${Config.opts.lrclibUrl}/api/search?${q}`, (code, results) => {
            if (id !== _requestId)
                return;
            if (code !== 200)
                return pick ? failed() : undefined;
            const usable = (results ?? []).filter(hasLyrics);
            usable.sort((a, b) => score(a) - score(b));
            candidates = usable.slice(0, 12).map(r => ({
                        id: r.id,
                        synced: !!r.syncedLyrics,
                        duration: r.duration,
                        label: `${r.artistName} — ${r.trackName}${r.albumName ? " · " + r.albumName : ""}`
                    }));
            if (pick)
                finish(key, usable[0] ?? null);
        });
    }

    // Lower is better: a matching length beats everything, then synced
    // beats plain. Entries only seconds long are broken uploads.
    function score(r) {
        const d = r.duration ?? 0;
        const diff = length > 0 ? Math.abs(d - length) : 0;
        return (diff <= 3 ? diff : 2000 + diff) + (r.syncedLyrics ? 0 : 1000) + (d < 30 ? 5000 : 0);
    }

    function failed() {
        status = "error";
        retry.restart();
    }

    function finish(key, data) {
        retry.attempt = 0;
        const parsed = data ? parse(data) : null;
        if (parsed) {
            parsed.id = data.id ?? 0;
            parsed.mismatch = length > 0 && data.duration > 0 && Math.abs(data.duration - length) > 3;
            _cache[key] = parsed;
        }
        apply(parsed);
    }

    // Use a specific LRCLIB version for this song from now on.
    function choose(id) {
        const choice = Object.assign({}, Store.db.lyricsChoice ?? {});
        choice[trackKey] = id;
        Store.db.lyricsChoice = choice;
        refetch();
    }

    function loadCandidates() {
        if (trackKey !== "")
            searchVersions(trackKey, _requestId, false);
    }

    function apply(parsed) {
        if (!parsed) {
            lines = [];
            synced = false;
            timingMismatch = false;
            chosenId = 0;
            status = "notfound";
            return;
        }
        synced = parsed.synced;
        lines = parsed.lines;
        timingMismatch = parsed.mismatch ?? false;
        chosenId = parsed.id ?? 0;
        status = "ready";
    }

    function hasLyrics(d) {
        return d && (d.instrumental || d.syncedLyrics || d.plainLyrics);
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

    // cb(httpStatus, json) — status 0 means the network request failed.
    function request(url, cb) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let data = null;
            try {
                data = JSON.parse(xhr.responseText);
            } catch (e) {}
            cb(xhr.status === 200 && data === null ? 0 : xhr.status, data);
        };
        xhr.open("GET", url);
        xhr.setRequestHeader("Lrclib-Client", "Islet (https://github.com/Claritys11/islet)");
        xhr.send();
    }

    // ── Sample lyrics ─────────────────────────────────────────────
    readonly property real demoLength: 36
    readonly property string demoLrc: [
        "[00:01.00] This is how your lyrics look",
        "[00:04.50] Every line glows as it's sung (as it's sung)",
        "[00:08.50] (Ooh, ooh, ooh)",
        "[00:11.50] A really long line wraps onto a second row instead of shrinking down",
        "[00:16.50] Background vocals answer back (answer back)",
        "[00:20.50] ",
        "[00:24.00] Change a setting and watch it here",
        "[00:28.00] Then press Done when it feels right (feels right)",
        "[00:33.00] "
    ].join("\n")
}
