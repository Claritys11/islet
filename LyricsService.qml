pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "link/fill.mjs" as Fill

// Follows an MPRIS player, fetches lyrics from LRCLIB and tracks the
// currently sung line and how far into it the singer is.
Singleton {
    id: root

    // Whatever is playing — the preferred player first if several are — and
    // when everything is paused, the one used last, so pausing YouTube Music
    // doesn't hand the lyrics back to a paused Spotify.
    readonly property MprisPlayer player: {
        const players = Mpris.players.values;
        const want = Config.opts.player.toLowerCase();
        const preferred = p => want !== "" && [p.identity, p.desktopEntry, p.dbusName].some(s => (s ?? "").toLowerCase().includes(want));
        const playing = players.filter(p => p.isPlaying);
        return playing.find(preferred) ?? playing[0] ?? (players.includes(_lastActive) ? _lastActive : null) ?? players.find(preferred) ?? players[0] ?? null;
    }
    property MprisPlayer _lastActive: null
    onPlayerChanged: if (player?.isPlaying)
        _lastActive = player
    Connections {
        target: root.player
        function onIsPlayingChanged() {
            if (root.player?.isPlaying)
                root._lastActive = root.player;
        }
    }

    // Browsers play YouTube, SoundCloud and the like, whose titles carry
    // extras ("(Official Video)", "Artist - Song") that need tidying.
    readonly property bool fromBrowser: /chrom|firefox|brave|vivaldi|opera|edge|zen|librewolf|floorp|epiphany/i.test(`${player?.identity ?? ""} ${player?.dbusName ?? ""}`)

    // Sample lyrics so settings can be previewed without music playing.
    property bool demo: false

    // Browser players get their names tidied (see tidy()).
    readonly property var _names: fromBrowser ? tidy(player?.trackTitle ?? "", player?.trackArtist ?? "") : null
    readonly property string title: demo ? "Sample Song" : _names?.title ?? player?.trackTitle ?? ""
    readonly property string artist: demo ? "Islet preview" : _names?.artistText ?? player?.trackArtist ?? ""
    readonly property real length: demo ? demoLength : player?.length ?? 0
    readonly property string artUrl: demo ? Qt.resolvedUrl("assets/demo-cover.jpg") : player?.trackArtUrl ?? ""
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

    // Where the current lyrics came from: "spicy" (Spicy Lyrics via the
    // Spicetify bridge, syllable-synced) or "lrclib".
    property string source: ""
    readonly property bool useSpicy: Config.opts.lyricsSource !== "lrclib"

    // Spotify's track id ("/com/spotify/track/<id>" in MPRIS), to match what
    // the bridge sends.
    readonly property string spotifyId: {
        const tid = String(player?.metadata?.["mpris:trackid"] ?? "");
        const m = tid.match(/track[:\/]([A-Za-z0-9]{22})$/);
        return m ? m[1] : "";
    }

    // Playback clock in seconds. Measurements — from the bridge when it's
    // connected (Spotify's own audio-side position), otherwise MPRIS polls —
    // feed a clock that advances with real time. Real jumps snap; small
    // disagreements are pulled in gently, the same filter Spicy Lyrics uses,
    // so the lyrics never stutter.
    property real position: 0
    property real _mPos: 0
    property real _mAt: 0
    property real _frameAt: 0
    property real _demoStart: 0
    // Spicy Lyrics leads its clock by 100 ms for audio latency; LRCLIB line
    // stamps benefit from a little more.
    readonly property real offset: (source === "spicy" ? Config.opts.spicyOffsetMs : Config.opts.offsetMs) / 1000
    readonly property real time: position + offset

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

    // The current line's fill as keys (link/fill.mjs), worked out once per
    // line; the DMS bar pill gets them too and fills the line by itself.
    readonly property var lineKeys: synced && lines[currentIndex] ? Fill.fillKeys(lines[currentIndex], mainDuration(currentIndex)) : []
    // 0 → 1: how much of the current line has been sung.
    readonly property real progress: synced ? Fill.fillAt(lineKeys, time) : 1

    function nextTime(i) {
        return lines[i + 1]?.time ?? (length > 0 ? length : (lines[i]?.time ?? 0) + 5);
    }

    // How fast this song is sung, in letters per second. LRC only says when
    // each line starts, but for back-to-back lines the gap between two starts
    // is about how long the first took to sing — so the median over those
    // pairs is the song's pace. (A ballad is ~5, fast pop or rap 10+.)
    readonly property real pace: {
        const rates = [];
        for (let i = 0; i < lines.length - 1; i++) {
            const l = lines[i];
            const gap = lines[i + 1].time - l.time;
            if (!l.interlude && l.main.length >= 4 && gap > 0.5 && gap < 12)
                rates.push(l.main.length / gap);
        }
        if (rates.length < 3)
            return 7;
        rates.sort((a, b) => a - b);
        return rates[rates.length >> 1];
    }

    // Without word timings, a line is filled at the song's pace (adjustable
    // with "Fill speed") and never runs past the next line. Lines before an
    // instrumental break end when they'd naturally be sung, not at the break.
    function mainDuration(i) {
        const l = lines[i];
        const gap = nextTime(i) - l.time;
        if (l.interlude)
            return gap;
        const sung = l.main.length / (pace * Config.opts.fillSpeed) * 1.1 + 0.3;
        return Math.max(0.3, Math.min(gap * 0.95, sung));
    }

    // Fill through timed syllables: each one fills from its start to its end,
    // and the fill holds between them. [{ s, e, from, to }] → 0..1
    function sylProgress(syl, t) {
        let p = 0;
        for (const x of syl) {
            if (t < x.s)
                break;
            p = t >= x.e ? x.to : x.from + (x.to - x.from) * (t - x.s) / Math.max(x.e - x.s, 0.01);
        }
        return p;
    }

    function lineProgress(i, t) {
        return lines[i] ? Fill.fillAt(Fill.fillKeys(lines[i], mainDuration(i)), t) : 0;
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
        // Timed background syllables: lit exactly while they're sung.
        if (l.bgSyl?.length) {
            const hold = Math.min(Config.opts.bgLinger, 0.6);
            const glow = t < l.bgStart - 0.1 ? 0 : t < l.bgEnd ? 1 : Math.max(0, 1 - (t - l.bgEnd) / Math.max(hold, 0.01));
            return { progress: sylProgress(l.bgSyl, t), glow };
        }
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
        player.position = Math.max(0, lines[index].time - offset + 0.05);
        resync(player.position);
    }

    function refetch() {
        delete _cache[trackKey];
        fetchLyrics();
    }

    // Record a measured position (seconds) taken at `at` (ms since epoch).
    function measure(pos, at) {
        _mPos = pos;
        _mAt = at;
    }

    // Jump straight to a position (seeks, pauses, track changes).
    function resync(pos) {
        measure(pos, Date.now());
        position = pos;
        _frameAt = Date.now();
    }

    function playerPosition() {
        player?.positionChanged();
        return player?.position ?? 0;
    }

    // ── Clock ─────────────────────────────────────────────────────
    // MPRIS doesn't push its position, so poll it — unless the bridge is
    // already sending Spotify's own, better clock for this track.
    Timer {
        running: root.player !== null && !root.demo
        repeat: true
        interval: 250
        onTriggered: {
            if (SpicyBridge.sampleFor(root.spotifyId))
                return;
            const reported = root.playerPosition();
            root.measure(reported, Date.now());
            if (!root.isPlaying)
                root.position = reported;
        }
    }

    Connections {
        target: SpicyBridge
        function onSampleChanged() {
            const s = SpicyBridge.sample;
            if (root.demo || !s || s.id !== root.spotifyId)
                return;
            root.measure(s.position, s.at);
            if (!s.playing)
                root.position = s.position;
        }
        function onLyricsArrived(id) {
            // Spicy Lyrics' syllable timing beats LRCLIB's lines: switch over
            // as soon as it shows up, even if LRCLIB answered first.
            if (root.useSpicy && !root.demo && id === root.spotifyId && root.trackKey !== "") {
                root._requestId++;
                retry.stop();
                root.apply(SpicyBridge.lyricsFor(id));
            }
        }
    }

    // Things drawing the fill as it moves (SmoothLyrics); with none, the
    // clock needn't run every frame, only wake as the next line starts.
    property int smoothUsers: 0
    readonly property bool smooth: smoothUsers > 0 || demo

    // The lyric time now, from the last measurement (whatever `position`
    // last caught up to).
    function timeNow() {
        return (isPlaying && !demo ? _mPos + (Date.now() - _mAt) / 1000 : position) + offset;
    }

    Timer {
        running: root.isPlaying && !root.smooth
        repeat: true
        // Just after the next line starts (between 50 ms and 1 s away).
        interval: Math.max(50, Math.min(1000, Math.ceil((root.nextTime(root.currentIndex) - root.time) * 1000) + 15))
        onTriggered: {
            root.position = root._mPos + (Date.now() - root._mAt) / 1000;
            root._frameAt = Date.now();
        }
    }

    FrameAnimation {
        running: root.isPlaying && root.smooth
        onTriggered: {
            const now = Date.now();
            // High-refresh monitors would otherwise redo every lyric binding
            // 144–240 times a second; the fill looks the same at 60.
            if (now - root._frameAt < 1000 / Config.opts.maxFps - 2)
                return;
            if (root.demo) {
                root._frameAt = now;
                root.position = ((now - root._demoStart) / 1000) % root.demoLength;
                return;
            }
            const elapsed = Math.min(Math.max(0, now - root._frameAt), 1000);
            root._frameAt = now;
            const measured = root._mPos + (now - root._mAt) / 1000;
            const predicted = root.position + elapsed / 1000;
            const error = measured - predicted;
            root.position = Math.abs(error) > 0.5 ? measured : predicted + error * (1 - Math.exp(-elapsed / 300));
        }
    }

    onIsPlayingChanged: if (player && !demo)
        resync(playerPosition())

    onDemoChanged: {
        if (demo) {
            _requestId++;
            apply(parse({ syncedLyrics: demoLrc }));
            _demoStart = Date.now();
            position = 0;
        } else {
            lines = [];
            fetchDebounce.restart();
            if (player)
                resync(playerPosition());
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
        const spicy = useSpicy ? SpicyBridge.lyricsFor(spotifyId) : null;
        if (spicy) {
            apply(spicy);
            return;
        }
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
        const names = fromBrowser ? tidy(title, artist) : { title, artist };
        const base = `artist_name=${encodeURIComponent(names.artist)}&track_name=${encodeURIComponent(names.title)}`;
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
    // Tries a few searches, loosest last, until one finds something: the
    // exact names, then the tidied ones, then free text. A loose match must
    // also have the right length, or it's likely a different song.
    function searchVersions(key, id, pick) {
        const t = tidy(title, artist);
        const api = `${Config.opts.lrclibUrl}/api/search?`;
        const enc = encodeURIComponent;
        const queries = [
            { url: api + `artist_name=${enc(artist)}&track_name=${enc(cleanTitle(title))}`, loose: false },
            { url: api + `artist_name=${enc(t.artist)}&track_name=${enc(t.title)}`, loose: false },
            { url: api + `q=${enc(t.artist + " " + t.title)}`, loose: true },
            { url: api + `q=${enc(t.full)}`, loose: true }
        ].filter((q, i, all) => all.findIndex(o => o.url === q.url) === i);
        const found = usable => {
            usable.sort((a, b) => score(a) - score(b));
            candidates = usable.slice(0, 12).map(r => ({
                        id: r.id,
                        synced: !!r.syncedLyrics,
                        duration: r.duration,
                        label: `${r.artistName} — ${r.trackName}${r.albumName ? " · " + r.albumName : ""}`
                    }));
            if (pick)
                finish(key, usable[0] ?? null);
        };
        const next = n => {
            if (n >= queries.length)
                return pick ? finish(key, null) : undefined;
            request(queries[n].url, (code, results) => {
                if (id !== _requestId)
                    return;
                if (code !== 200)
                    return pick ? failed() : undefined;
                let usable = (results ?? []).filter(hasLyrics);
                if (queries[n].loose && length > 0)
                    usable = usable.filter(r => Math.abs((r.duration ?? 0) - length) <= 3);
                if (usable.length === 0)
                    return next(n + 1);
                found(usable);
            });
        };
        next(0);
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
            source = "";
            status = "notfound";
            return;
        }
        source = parsed.source ?? "lrclib";
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

    // Title and artists as LRCLIB knows them. Video sites add tags to titles,
    // put "Artist - Song" in the title, name channels "Artist - Topic" or
    // "ArtistVEVO", and YouTube Music joins artists in your language
    // ("Lady Gaga dan Bruno Mars").
    function tidy(t, a) {
        const squash = x => x.toLowerCase().replace(/[\s.,'’&_-]/g, "");
        let artist = a.replace(/\s*-\s*topic$/i, "").replace(/vevo$/i, "").replace(/\s+official( channel)?$/i, "").trim();
        const full = t
            .replace(/\s*[(\[【][^)\]】]*\b(official|video|audio|lyrics?|lirik|mv|m\/v|visuali[sz]er|hd|4k|explicit|color coded)\b[^)\]】]*[)\]】]/gi, "")
            .replace(/\s*[(\[](feat|ft|with)\.?\s[^)\]]*[)\]]/gi, "")
            .replace(/\s+(feat|ft)\.?\s.*$/i, "")
            .replace(/\s*[|｜].*$/, "")
            .replace(/\s+(official\s+)?(music\s+)?(m\/?v|video|audio|lyric video|visuali[sz]er)$/i, "")
            .replace(/^["“'‘](.*)["”'’]$/, "$1")
            .trim() || t;
        let title = full;
        // "Artist - Song", when the part before the dash names the channel
        // (so "Song - Remix" on YouTube Music stays whole).
        const dash = full.split(/ [-–—] /);
        if (dash.length > 1 && artist !== "" && squash(dash[0]).includes(squash(artist).slice(0, 12))) {
            artist = dash[0];
            title = dash.slice(1).join(" - ");
        }
        // K-pop style: "NewJeans (뉴진스) 'Super Shy'" — the song is quoted.
        const quoted = title.match(/^(.*?)\s*['‘"“]([^'’"”]+)['’"”]\s*$/);
        if (quoted) {
            if (quoted[1].trim() !== "")
                artist = quoted[1].replace(/\s*\([^)]*\)/g, "").trim();
            title = quoted[2].trim();
        }
        const artists = artist.split(/\s*,\s*|\s*&\s*|\s+(?:x|and|dan|und|y|et|e|feat\.?|ft\.?|with|vs\.?)\s+/i).filter(s => s !== "");
        return { title, full, artist: artists[0] ?? artist, artists, artistText: artists.join(", ") || artist };
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
        const len = Math.max(text.replace(/\s+$/, "").length, 1);
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
