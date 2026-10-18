// NAME: Islet Bridge
// AUTHOR: Claritys11
// DESCRIPTION: Shares the lyrics Spicy Lyrics already loaded, and Spotify's exact playback position, with Islet (https://github.com/Claritys11/islet).
// VERSION: 1.0.0

// How it works: Spicy Lyrics fetches syllable-synced lyrics for every song and
// caches them in Cache Storage. This extension reads that cache (it never calls
// Spicy Lyrics' servers itself) and posts the lyrics, plus position samples
// taken the same way Spicy Lyrics takes them, to Islet's local receiver on
// 127.0.0.1. Nothing leaves your computer.
(function isletBridge() {
    const Player = globalThis.Spicetify?.Player;
    const Platform = globalThis.Spicetify?.Platform;
    if (!Player?.data || !Platform?.PlayerAPI) {
        setTimeout(isletBridge, 300);
        return;
    }

    const port = Number(localStorage.getItem("islet-bridge:port")) || 47821;
    const endpoint = `http://127.0.0.1:${port}`;
    const POSITION_INTERVAL = 250;
    const RESEND_INTERVAL = 15000;

    let current = { id: null, lyrics: null, sentAt: 0 };
    let online = false;

    function trackId() {
        const uri = Player.data?.item?.uri ?? "";
        return uri.startsWith("spotify:track:") ? uri.split(":")[2] : null;
    }

    async function post(path, body) {
        try {
            const res = await fetch(endpoint + path, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(body)
            });
            online = res.ok;
        } catch {
            // Islet isn't running; try again on the next sample.
            online = false;
        }
        return online;
    }

    // ── Lyrics: read Spicy Lyrics' cache ──────────────────────────
    async function readSpicyCache(id) {
        if (!("caches" in globalThis))
            return null;
        // The store name carries a version suffix (…_g1); newest first.
        const names = (await caches.keys()).filter(n => n.startsWith("SpicyLyrics_LyricsStore")).sort().reverse();
        for (const name of names) {
            const res = await (await caches.open(name)).match(`/${id}`);
            if (!res)
                continue;
            try {
                const wrapped = await res.json();
                if (wrapped?.Content && !(wrapped.ExpiresAt < Date.now()))
                    return wrapped.Content;
            } catch {}
        }
        return null;
    }

    async function sendLyrics(force) {
        const id = trackId();
        if (!id)
            return;
        if (current.id !== id)
            current = { id, lyrics: null, sentAt: 0 };
        if (!current.lyrics)
            current.lyrics = await readSpicyCache(id);
        if (!current.lyrics)
            return;
        if (!force && Date.now() - current.sentAt < RESEND_INTERVAL)
            return;
        const item = Player.data.item;
        const ok = await post("/lyrics", {
            id,
            title: item?.name ?? item?.metadata?.title ?? "",
            artist: item?.artists?.map(a => a.name).join(", ") ?? item?.metadata?.artist_name ?? "",
            duration: (Player.getDuration?.() ?? 0) / 1000,
            lyrics: current.lyrics
        });
        if (ok)
            current.sentAt = Date.now();
    }

    // Spicy Lyrics needs a moment after a song change to fetch; poll its
    // cache until the lyrics show up (or give up after ~20 s).
    let lyricsPoll = null;
    function watchForLyrics() {
        clearInterval(lyricsPoll);
        let tries = 0;
        lyricsPoll = setInterval(async () => {
            await sendLyrics(true);
            if (current.lyrics || ++tries > 40)
                clearInterval(lyricsPoll);
        }, 500);
    }

    // ── Position: the same sources Spicy Lyrics uses ──────────────
    // getPositionState is the audio-side truth, but on some builds it stalls;
    // then fall back to the player state, extrapolated to now.
    let last = { raw: null, changedAt: 0 };

    async function samplePosition() {
        const id = trackId();
        const playing = Player.isPlaying();
        const state = Platform.PlayerAPI._state;
        const startedAt = Date.now();
        let position = null;
        let at = startedAt;

        try {
            const res = await Platform.PlayerAPI._contextPlayer.getPositionState({});
            // Async: the value was true somewhere between asking and answering.
            at = startedAt + (Date.now() - startedAt) / 2;
            const raw = Number(res?.position);
            if (Number.isFinite(raw)) {
                if (raw !== last.raw)
                    last = { raw, changedAt: at };
                // Healthy sources move every poll; a stuck one is ignored.
                if (!playing || at - last.changedAt < 500)
                    position = raw;
            }
        } catch {}

        if (position === null && state) {
            position = playing ? state.positionAsOfTimestamp + (at - state.timestamp) : state.positionAsOfTimestamp;
        }
        if (position === null)
            position = Player.getProgress();

        post("/position", { id, position: position / 1000, at, playing });
    }

    Player.addEventListener("songchange", watchForLyrics);
    Player.addEventListener("onplaypause", samplePosition);
    setInterval(samplePosition, POSITION_INTERVAL);
    // Resend now and then so Islet catches up if it was (re)started later.
    setInterval(() => sendLyrics(false), RESEND_INTERVAL);
    watchForLyrics();
})();
