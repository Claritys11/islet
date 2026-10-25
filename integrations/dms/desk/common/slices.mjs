// islet's state line, cut into the parts the desktop widgets draw. A tick
// that only moves the karaoke progress or the visualizer leaves every part
// the same, so IsletClient can skip reassigning it and the widgets' lists
// and buttons aren't rebuilt 30 times a second (review C1).
export function splitState(msg) {
    return {
        track: {
            hasTrack: !!msg?.hasTrack,
            title: msg?.title ?? "",
            artist: msg?.artist ?? "",
            art: artUrl(msg?.art),
            playing: !!msg?.playing
        },
        lyrics: msg?.lyrics ?? null,
        tasks: msg?.tasks ?? null,
        pomodoro: msg?.pomodoro ?? null,
        // Islet's notch in the DMS dashboard (tab and card).
        day: msg?.day ?? null,
        shelf: msg?.shelf ?? null,
        checklist: msg?.checklist ?? null
    };
}

// islet already sends art as a file:// URL (ArtCache); a bare path from an
// older islet still gets one, so Image never sees "file://file:///…".
export function artUrl(art) {
    if (!art)
        return "";
    return art.startsWith("/") ? "file://" + art : art;
}
