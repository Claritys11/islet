pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Receives lyrics and playback position from the Islet Bridge Spicetify
// extension (spicetify/islet-bridge.js), which reads what Spicy Lyrics has
// already loaded inside Spotify. Syllable timing plus Spotify's own clock is
// what makes Spicy Lyrics line up so precisely; this brings both to Islet.
Singleton {
    id: root

    readonly property bool enabled: Config.opts.lyricsSource !== "lrclib"
    readonly property string script: Qt.resolvedUrl("bridge/islet-bridge.py").toString().replace(/^file:\/\//, "")

    // Converted lyrics per Spotify track id (only the last few are kept).
    property var lyrics: ({})
    property var _order: []
    property var _raw: ({})
    // Latest position sample: { id, position (s), at (ms epoch), playing, received (ms) }
    property var sample: null
    property real now: Date.now()
    // The extension has been heard from recently.
    readonly property bool connected: sample !== null && now - sample.received < 3000

    signal lyricsArrived(string id)

    function lyricsFor(id) {
        return id ? lyrics[id] ?? null : null;
    }

    // A fresh position sample for this track, or null.
    function sampleFor(id) {
        return sample && sample.id === id && Date.now() - sample.received < 1500 ? sample : null;
    }

    Timer {
        running: root.enabled
        repeat: true
        interval: 1000
        onTriggered: root.now = Date.now()
    }

    Process {
        id: server
        running: root.enabled
        command: ["python3", "-I", root.script, String(Config.opts.bridgePort)]
        stdout: SplitParser {
            onRead: line => {
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (msg.kind === "position") {
                    msg.received = Date.now();
                    root.sample = msg;
                } else if (msg.kind === "lyrics" && msg.id) {
                    // The extension re-sends every 15 s; an unchanged copy
                    // must not rebuild the lyrics (that would flash).
                    const raw = JSON.stringify(msg.lyrics);
                    if (root._raw[msg.id] === raw)
                        return;
                    root._raw[msg.id] = raw;
                    const converted = root.convert(msg.lyrics);
                    if (!converted)
                        return;
                    const next = Object.assign({}, root.lyrics);
                    next[msg.id] = converted;
                    root._order = root._order.filter(i => i !== msg.id).concat([msg.id]);
                    while (root._order.length > 8) {
                        const old = root._order.shift();
                        delete next[old];
                        delete root._raw[old];
                    }
                    root.lyrics = next;
                    root.lyricsArrived(msg.id);
                }
            }
        }
        // Port busy or python missing: try again in a bit rather than spin.
        onExited: if (root.enabled)
            restart.start()
    }

    Timer {
        id: restart
        interval: 5000
        onTriggered: server.running = root.enabled
    }

    // ── Spicy Lyrics format → Islet lines ─────────────────────────
    // Syllable lyrics:  { Type: "Syllable", Content: [{ Lead: { StartTime, EndTime,
    //                     Syllables: [{ Text, StartTime, EndTime, IsPartOfWord }] },
    //                     Background?: [{ … same … }] }] }   (times in seconds)
    // Line lyrics:      { Type: "Line", Content: [{ Text, StartTime, EndTime }] }
    // Static lyrics:    { Type: "Static", Lines: [{ Text }] }
    function convert(data) {
        if (!data)
            return null;
        let lines = [];
        if (data.Type === "Syllable") {
            for (const item of data.Content ?? []) {
                if (!item.Lead?.Syllables?.length)
                    continue;
                const lead = joinSyllables(item.Lead.Syllables);
                const bgs = (item.Background ?? []).filter(b => b.Syllables?.length).map(b => joinSyllables(b.Syllables));
                const bg = mergeGroups(bgs);
                lines.push({
                    time: item.Lead.StartTime,
                    end: item.Lead.EndTime,
                    text: lead.text,
                    main: lead.text,
                    bg: bg.text,
                    bgOnly: false,
                    interlude: false,
                    words: null,
                    syl: lead.syl,
                    bgSyl: bg.syl,
                    bgStart: bg.syl.length ? bg.syl[0].s : 0,
                    bgEnd: bg.syl.length ? bg.syl[bg.syl.length - 1].e : 0
                });
            }
        } else if (data.Type === "Line") {
            for (const item of data.Content ?? []) {
                const text = (item.Text ?? "").trim();
                if (text === "")
                    continue;
                const line = LyricsService.makeLine(item.StartTime, text, null);
                line.end = item.EndTime;
                lines.push(line);
            }
        } else if (data.Type === "Static") {
            const plain = (data.Lines ?? []).map(l => (l.Text ?? "").trim()).filter(t => t !== "");
            return plain.length ? { synced: false, lines: plain.map(t => LyricsService.makeLine(0, t, null)) } : null;
        }
        if (lines.length === 0)
            return null;
        lines.sort((a, b) => a.time - b.time);

        // Dots for the gaps, like Spicy Lyrics: before the first line and
        // wherever the singer pauses for a while.
        const out = [];
        if (lines[0].time > 2)
            out.push(LyricsService.makeLine(0, LyricsService.interludeText, null));
        for (let i = 0; i < lines.length; i++) {
            out.push(lines[i]);
            const next = lines[i + 1];
            if (next && next.time - lines[i].end > 4)
                out.push(LyricsService.makeLine(lines[i].end + 0.3, LyricsService.interludeText, null));
        }
        return { synced: true, lines: out, source: "spicy" };
    }

    // Join syllables into text, keeping each syllable's character range so the
    // fill can follow it: [{ s, e, from, to }] with from/to as 0..1 of the text.
    function joinSyllables(syllables) {
        let text = "";
        const ranges = [];
        for (let i = 0; i < syllables.length; i++) {
            const syl = syllables[i];
            const from = text.length;
            // Spicy Lyrics' data carries zero-width spaces between syllables.
            text += (syl.Text ?? "").replace(/[\u200b-\u200d\ufeff]/g, "");
            ranges.push({ s: syl.StartTime, e: syl.EndTime, from, to: text.length });
            if (!syl.IsPartOfWord && i < syllables.length - 1)
                text += " ";
        }
        const len = Math.max(text.length, 1);
        return { text, syl: ranges.map(r => ({ s: r.s, e: r.e, from: r.from / len, to: r.to / len })) };
    }

    // Several background groups on one line become one text, "a  b".
    function mergeGroups(groups) {
        if (groups.length === 0)
            return { text: "", syl: [] };
        const text = groups.map(g => g.text).join("  ");
        const len = Math.max(text.length, 1);
        const syl = [];
        let offset = 0;
        for (const g of groups) {
            const glen = g.text.length;
            for (const r of g.syl)
                syl.push({ s: r.s, e: r.e, from: (offset + r.from * glen) / len, to: (offset + r.to * glen) / len });
            offset += glen + 2;
        }
        return { text, syl };
    }
}
