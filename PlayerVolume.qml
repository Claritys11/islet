pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "media/volume.mjs" as Volume

// The playing app's own volume (not the system's), for scrolling on the
// pill. Its PipeWire streams first, like a mixer's per-app slider: always
// current, and it works for any player. Else MPRIS, but not for Chrome
// (as DankMaterialShell's media widget does), and Spotify's MPRIS never
// reports a change back, so steps from it would go nowhere.
Singleton {
    id: root

    readonly property var player: LyricsService.player

    // Apps' playback streams. A node's properties and volume only fill in
    // once it's bound, so all of them are tracked, then matched.
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.isStream && !n.isSink)
    PwObjectTracker {
        objects: root.outputs
    }
    readonly property var streams: {
        if (!player)
            return [];
        const list = outputs.filter(n => n.audio && n.properties).map(n => ({ app: n.properties["application.name"], binary: n.properties["application.process.binary"], media: n.properties["media.name"], node: n }));
        return Volume.pickStreams(list, { identity: player.identity, desktopEntry: player.desktopEntry }).map(s => s.node);
    }
    readonly property bool viaMpris: streams.length === 0 && !!player && player.canControl && player.volumeSupported && !/chrom/i.test(player.identity + player.desktopEntry)

    // 0–1, or -1 when there's nothing to turn.
    readonly property real level: streams.length ? streams[0].audio.volume : viaMpris ? player.volume : -1

    // `steps` of 5% up (+) or down (−).
    function nudge(steps) {
        if (streams.length) {
            const v = Volume.nudge(streams[0].audio.volume, steps);
            for (const s of streams)
                s.audio.volume = v;
        } else if (viaMpris) {
            player.volume = Volume.nudge(player.volume, steps);
        }
    }
}
