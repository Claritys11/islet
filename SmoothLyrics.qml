import QtQuick

// Put one where Islet draws the karaoke fill or the playback position as it
// moves (the lyrics overlay, the notch's pill and Media tab): while it's
// active, LyricsService runs its clock every frame. With none active, the
// clock wakes only when the next line starts.
QtObject {
    property bool active: false
    property bool _counted: false

    function sync() {
        if (active === _counted)
            return;
        LyricsService.smoothUsers += active ? 1 : -1;
        _counted = active;
    }
    onActiveChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (_counted)
        LyricsService.smoothUsers -= 1
}
