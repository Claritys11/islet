import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "common"
import "common/rich.mjs" as Rich
import "common/mdedit.mjs" as Md

// end4-pC's Notes, backed by your Notion "Notes" database through islet:
// newest notes as coloured cards (Tipe / Topik chips); click one to read it
// with its formatting; ↗ opens it in the Notion app when it's running (the
// web otherwise). "+" writes a note. Drafts are DMS Notepad's own tabs
// (NotepadStorageService, ~/.local/state/dms/notepad-*), so the same notes
// show in the notepad and here, live; they stay on this computer until you
// send one to Notion. The toolbar and Notion's shortcuts (FormatBar) write
// Markdown that islet turns into Notion formatting.
DesktopPluginComponent {
    id: root

    minWidth: 300
    minHeight: 300
    // Only while writing a note, or about to (pointer on "+" or on a draft):
    // DMS lets the compositor focus a widget only if it wants keys at the
    // moment it's clicked (review I3).
    property bool acceptsKeyboardFocus: root.writing || card.actionHovered || draftHover.hovered

    property string tipe: pluginData.tipe ?? ""
    property int limit: pluginData.limit ?? 30

    property var notes: []
    property string error: ""
    property bool loading: false
    property int listSeq: 0
    property string openId: ""
    property var openLines: []
    property bool openCut: false
    property bool openLoading: false

    // Drafts: the notepad's tabs. `texts` caches each tab's text by id (for
    // titles and to hide empty ones); `loadedId` is the tab in the editor
    // and `lastSaved` what its file holds.
    readonly property var tabs: NotepadStorageService.tabs
    property var texts: ({})
    property var loadedId: -1
    property string lastSaved: ""
    property bool writing: false
    property var sendingId: -1
    property var confirmDiscard: -1
    property string hint: ""
    property bool _switching: false
    readonly property var loadedTab: root.tabs.find(t => t.id === root.loadedId) ?? null
    readonly property var shownDrafts: root.tabs.filter(t => (root.texts[t.id] ?? "").trim() !== "")
    readonly property string legacyDrafts: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/deskw/notes-drafts.json`

    Ref {
        service: NotepadStorageService
    }

    Requester {
        id: requester
    }

    // A reply that comes after a newer load (the tipe filter arriving just
    // after startup, a changed limit) is dropped (review M2).
    function load(): void {
        if (!IsletClient.connected) {
            root.error = "islet isn't running";
            return;
        }
        const seq = ++root.listSeq;
        root.loading = true;
        requester.request("notes-list", { limit: root.limit, tipe: root.tipe }, (ok, data, err) => {
            if (seq !== root.listSeq)
                return;
            root.loading = false;
            if (ok) {
                root.notes = data;
                root.error = "";
            } else {
                // Keep what we had; say why it didn't refresh.
                root.error = err;
            }
        });
    }

    function toggle(note): void {
        if (root.openId === note.id) {
            root.openId = "";
            return;
        }
        root.openId = note.id;
        root.openLines = [];
        root.openCut = false;
        root.openLoading = true;
        requester.request("note-get", { id: note.id }, (ok, data, err) => {
            if (root.openId !== note.id)
                return;
            root.openLoading = false;
            root.openLines = ok ? Rich.blocksToRich(data.blocks) : [{ type: "paragraph", html: err, depth: 0 }];
            root.openCut = ok && data.cut;
        }, 60000);
    }

    // A Notion page in the desktop app when it's open, else in the browser;
    // other links only when they're http(s)/mailto (review M8). The [n]
    // keeps pgrep from finding this very shell line.
    function openLink(url): void {
        const safe = Rich.safeLink(url);
        if (!safe)
            return;
        const app = Rich.notionAppUrl(safe);
        if (app === null) {
            Qt.openUrlExternally(safe);
            return;
        }
        Quickshell.execDetached(["sh", "-c", 'if pgrep -f "[n]otion-app|/[o]pt/Notion|[n]otion-desktop" >/dev/null; then exec xdg-open "$1"; else exec xdg-open "$2"; fi', "sh", app, safe]);
    }

    // —— Drafts (DMS Notepad tabs) ——

    function tabTitle(tab): string {
        const t = Md.draftTitle(tab.id === root.loadedId && root.writing ? editor.text : (root.texts[tab.id] ?? ""));
        return tab.isTemporary ? (t || IsletClient.t("New note", "Catatan baru")) : tab.title;
    }

    function setText(id, text): void {
        root.texts = Object.assign({}, root.texts, { [id]: text });
    }

    // Every tab's text, from the notepad's live buffer or its file.
    function refreshTexts(): void {
        NotepadStorageService.tabs.forEach((tab, i) => {
            NotepadStorageService.loadTabContent(i, content => {
                // DMS can destroy this widget before the file is read.
                if (!root)
                    return;
                const buffer = NotepadStorageService.getSessionBuffer(tab.id);
                root.setText(tab.id, buffer !== undefined ? buffer.content : content);
            }, () => {});
        });
    }

    // The editor's text out to the notepad: its live buffer at once (an
    // open notepad shows it), the file for a scratch tab. A file tab
    // (`final`: leaving it, Ctrl+S) is written to its own file only then.
    function flush(final): void {
        saveTimer.stop();
        const tab = root.loadedTab;
        if (!tab || root._switching)
            return;
        const text = editor.text;
        root.setText(tab.id, text);
        if (text === root.lastSaved)
            return;
        NotepadStorageService.setSessionBuffer(tab.id, text, root.lastSaved);
        if (!tab.isTemporary && !final)
            return;
        const index = NotepadStorageService.tabs.indexOf(tab);
        NotepadStorageService.saveTabContent(index, text);
        root.lastSaved = text;
        NotepadStorageService.clearSessionBuffer(tab.id);
        const title = Md.draftTitle(text);
        if (tab.isTemporary && title !== "" && title !== tab.title)
            NotepadStorageService.renameTab(index, title);
    }

    // The notepad's current tab into the editor.
    function loadCurrent(): void {
        const index = NotepadStorageService.currentTabIndex;
        const tab = NotepadStorageService.tabs[index];
        if (!tab)
            return;
        NotepadStorageService.loadTabContent(index, content => {
            if (!root || NotepadStorageService.tabs[NotepadStorageService.currentTabIndex]?.id !== tab.id)
                return;
            const buffer = NotepadStorageService.getSessionBuffer(tab.id);
            root._switching = true;
            root.loadedId = tab.id;
            root.lastSaved = buffer !== undefined ? buffer.baseline : content;
            editor.text = buffer !== undefined ? buffer.content : content;
            root._switching = false;
            root.setText(tab.id, editor.text);
            editor.cursorPosition = editor.length;
            Qt.callLater(() => editor.forceActiveFocus());
        }, () => {
            if (root)
                root.error = IsletClient.t("Too big for the widget — open it in Notepad", "File terlalu besar untuk widget — buka di Notepad");
        });
    }

    function show(index): void {
        root.flush(true);
        root.confirmDiscard = -1;
        root.writing = true;
        if (index === NotepadStorageService.currentTabIndex)
            root.loadCurrent();
        else
            NotepadStorageService.switchToTab(index);
        Qt.callLater(() => editor.forceActiveFocus());
    }

    // An empty scratch tab if there is one, else a new one.
    function newDraft(): void {
        root.flush(true);
        const blank = NotepadStorageService.tabs.findIndex(t => t.isTemporary && (root.texts[t.id] ?? "").trim() === "");
        if (blank >= 0)
            return root.show(blank);
        root.writing = true;
        root._switching = true;
        editor.text = "";
        root._switching = false;
        root.loadedId = -1;
        NotepadStorageService.createNewTab();
        Qt.callLater(() => editor.forceActiveFocus());
    }

    function close(): void {
        root.flush(true);
        root.writing = false;
        root.confirmDiscard = -1;
    }

    // Two clicks: the first only asks. A scratch tab and its file go; a
    // file tab is only closed (the file stays).
    function discard(id): void {
        if (root.confirmDiscard !== id) {
            root.confirmDiscard = id;
            return;
        }
        root.confirmDiscard = -1;
        const index = NotepadStorageService.tabs.findIndex(t => t.id === id);
        if (index < 0)
            return;
        if (id === root.loadedId)
            root.loadedId = -1;
        NotepadStorageService.closeTab(index);
    }

    // One send at a time, and a wait longer than islet's own Notion retries,
    // so a slow save isn't shown as failed and then saved twice (review I1).
    // A scratch tab is closed once Notion has the note; a file tab stays.
    function send(): void {
        root.flush(true);
        const tab = root.loadedTab;
        if (!tab || root.sendingId !== -1)
            return;
        const text = editor.text;
        if (text.trim() === "") {
            root.error = "empty note";
            return;
        }
        root.sendingId = tab.id;
        root.error = "";
        requester.request("note-create", { markdown: text }, (ok, data, err) => {
            root.sendingId = -1;
            if (!ok) {
                root.error = err;
                return;
            }
            const index = NotepadStorageService.tabs.findIndex(t => t.id === tab.id);
            if (tab.isTemporary && index >= 0) {
                if (tab.id === root.loadedId)
                    root.loadedId = -1;
                NotepadStorageService.closeTab(index);
                root.writing = false;
            } else {
                root.hint = "Terkirim ke Notion";
                hintTimer.restart();
            }
            root.load();
        }, 150000);
    }

    // Once: drafts from before the notepad was shared become notepad tabs.
    property var migrating: []
    function migrate(saved): void {
        const left = (saved ?? []).filter(d => typeof d?.text === "string" && d.text.trim() !== "");
        root.migrating = left;
        Quickshell.execDetached(["mv", "-f", root.legacyDrafts, root.legacyDrafts + ".migrated"]);
        root.migrateNext();
    }
    function migrateNext(): void {
        if (root.migrating.length === 0)
            return;
        const tab = NotepadStorageService.createNewTab();
        root.pendingMigration = { id: tab.id, text: root.migrating[0].text };
        root.migrating = root.migrating.slice(1);
    }
    property var pendingMigration: null

    function onKey(event): void {
        const ctrl = event.modifiers & Qt.ControlModifier, shift = event.modifiers & Qt.ShiftModifier;
        const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
        let done = true;
        if (ctrl && enter)
            root.send();
        else if (event.key === Qt.Key_Escape)
            root.close();
        else if (ctrl && !shift && event.key === Qt.Key_S) {
            root.flush(true);
            root.hint = "Tersimpan";
            hintTimer.restart();
        } else if (ctrl && !shift && event.key === Qt.Key_N)
            root.newDraft();
        else
            done = formatBar.handleKey(event);
        event.accepted = done;
    }

    Component.onCompleted: {
        load();
        if (NotepadStorageService.metadataLoaded)
            refreshTexts();
    }
    onTipeChanged: load()
    onLimitChanged: load()
    Component.onDestruction: flush(true)

    Connections {
        target: NotepadStorageService
        function onMetadataLoadedChanged() {
            root.refreshTexts();
        }
        function onTabsChanged() {
            const p = root.pendingMigration;
            const index = p ? NotepadStorageService.tabs.findIndex(t => t.id === p.id) : -1;
            if (index >= 0) {
                root.pendingMigration = null;
                NotepadStorageService.saveTabContent(index, p.text);
                NotepadStorageService.renameTab(index, Md.draftTitle(p.text) || IsletClient.t("Note", "Catatan"));
                root.setText(p.id, p.text);
                Qt.callLater(root.migrateNext);
            }
            refreshDebounce.restart();
        }
        function onCurrentTabIndexChanged() {
            if (root.writing && !root.pendingMigration) {
                root.flush(true);
                root.loadCurrent();
            }
        }
        // The notepad typed into the tab we show: take it while we're not
        // typing ourselves and have nothing unsaved.
        function onSessionBufferRevisionChanged() {
            const buffer = NotepadStorageService.getSessionBuffer(root.loadedId);
            if (buffer !== undefined)
                root.setText(root.loadedId, buffer.content);
            if (!root.writing || editor.activeFocus || buffer === undefined || buffer.content === editor.text || editor.text !== root.lastSaved)
                return;
            root._switching = true;
            editor.text = buffer.content;
            root.lastSaved = buffer.baseline;
            root._switching = false;
        }
    }

    Timer {
        id: refreshDebounce
        interval: 300
        onTriggered: root.refreshTexts()
    }

    FileView {
        path: root.legacyDrafts
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text()).drafts;
                if (NotepadStorageService.metadataLoaded)
                    root.migrate(saved);
                else
                    migrateWhenReady.saved = saved;
            } catch (e) {}
        }
    }
    Connections {
        id: migrateWhenReady
        property var saved: null
        target: NotepadStorageService
        enabled: saved !== null
        function onMetadataLoadedChanged() {
            const saved = migrateWhenReady.saved;
            migrateWhenReady.saved = null;
            root.migrate(saved);
        }
    }

    Timer {
        id: saveTimer
        interval: 600
        onTriggered: root.flush(false)
    }

    // A "hapus?" not confirmed within 3 s goes back to ×.
    Timer {
        interval: 3000
        running: root.confirmDiscard !== -1
        onTriggered: root.confirmDiscard = -1
    }

    Timer {
        id: hintTimer
        interval: 2000
        onTriggered: root.hint = ""
    }

    Connections {
        target: IsletClient
        function onConnectedChanged() {
            if (IsletClient.connected)
                root.load();
        }
    }

    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: true
        onTriggered: root.load()
    }

    component Chip: Rectangle {
        id: chip
        property string text: ""
        property bool active: false
        property bool danger: false
        property color fg: Theme.onPrimaryContainer
        signal clicked()
        height: 26
        width: chipLabel.implicitWidth + 20
        radius: 13
        color: chip.danger ? Theme.error : chip.active ? Theme.primary : Qt.alpha(Theme.onPrimaryContainer, chipArea.containsMouse ? 0.18 : 0.1)
        Text {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.text
            textFormat: Text.PlainText
            color: chip.danger ? Theme.onError : chip.active ? Theme.onPrimary : chip.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    DeskCard {
        id: card
        anchors.fill: parent
        title: "Notes"
        actionIcon: root.writing ? "×" : "+"
        cardColor: Theme.primaryContainer
        textColor: Theme.onPrimaryContainer
        accentColor: Theme.primary
        radius: Theme.cornerRadius * 1.5
        fontFamily: Theme.fontFamily
        onActionClicked: root.writing ? root.close() : root.newDraft()

        // —— Writing ——
        Column {
            id: writer
            visible: root.writing
            anchors.fill: parent
            spacing: 6

            // The drafts as tabs: click to switch, × twice to throw away.
            Flickable {
                width: parent.width
                height: 26
                contentWidth: tabs.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Row {
                    id: tabs
                    spacing: 4
                    Repeater {
                        model: root.tabs
                        Chip {
                            required property var modelData
                            required property int index
                            readonly property bool isCurrent: modelData.id === root.loadedId
                            text: root.tabTitle(modelData)
                                + (modelData.id === root.sendingId ? "  ⏳" : isCurrent ? (root.confirmDiscard === modelData.id ? IsletClient.t("  delete?", "  hapus?") : "  ×") : "")
                            active: isCurrent
                            danger: root.confirmDiscard === modelData.id
                            onClicked: isCurrent ? root.discard(modelData.id) : root.show(index)
                        }
                    }
                    Chip {
                        text: "+"
                        onClicked: root.newDraft()
                    }
                }
            }

            FormatBar {
                id: formatBar
                width: parent.width
                target: editor
                textColor: Theme.onPrimaryContainer
                accentColor: Theme.primary
                fontFamily: Theme.fontFamily
                fontSize: Theme.fontSizeSmall
                onHintChanged: root.hint = hint
            }

            Rectangle {
                width: parent.width
                height: Math.max(80, writer.height - y - footer.height - writer.spacing)
                radius: 14
                color: Qt.alpha(Theme.onPrimaryContainer, 0.1)
                border.color: Theme.primary
                border.width: 1
                Flickable {
                    id: flick
                    anchors.fill: parent
                    anchors.margins: 10
                    contentHeight: editor.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    // Keep the cursor in view while typing (review M7).
                    function ensureVisible(r) {
                        if (contentY >= r.y)
                            contentY = r.y;
                        else if (contentY + height <= r.y + r.height)
                            contentY = r.y + r.height - height;
                    }
                    TextEdit {
                        id: editor
                        width: flick.width
                        wrapMode: TextEdit.Wrap
                        color: Theme.onPrimaryContainer
                        selectionColor: Theme.primary
                        selectedTextColor: Theme.onPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMedium
                        selectByMouse: true
                        persistentSelection: true
                        readOnly: root.sendingId !== -1 && root.sendingId === root.loadedId
                        onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
                        onTextChanged: {
                            if (!root._switching)
                                saveTimer.restart();
                        }
                        Keys.onPressed: event => root.onKey(event)
                        Text {
                            visible: !editor.text
                            text: IsletClient.t("Title on the first line\nSelect text, then the toolbar or Ctrl+B, Ctrl+I…\nTab for a sub-list", "Judul di baris pertama\nPilih teks lalu pakai toolbar atau Ctrl+B, Ctrl+I…\nTab untuk sub-list")
                            color: Qt.alpha(Theme.onPrimaryContainer, 0.45)
                            font: editor.font
                        }
                    }
                }
            }

            Item {
                id: footer
                width: parent.width
                height: 30
                Text {
                    anchors.left: parent.left
                    anchors.right: sendBtn.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: root.error !== "" ? root.error : root.hint !== "" ? root.hint
                        : root.loadedTab && !root.loadedTab.isTemporary ? root.loadedTab.title + IsletClient.t(" · Ctrl+S saves", " · Ctrl+S simpan") : IsletClient.t("Saved by itself · also in DMS's Notepad", "Tersimpan otomatis · juga di Notepad DMS")
                    color: root.error !== "" ? Theme.error : Qt.alpha(Theme.onPrimaryContainer, 0.6)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall - 1
                }
                Rectangle {
                    id: sendBtn
                    anchors.right: parent.right
                    width: sendText.implicitWidth + 24
                    height: 30
                    radius: 15
                    color: Theme.primary
                    opacity: root.sendingId !== -1 ? 0.6 : 1
                    Text {
                        id: sendText
                        anchors.centerIn: parent
                        text: root.sendingId !== -1 ? IsletClient.t("Sending…", "Mengirim…") : IsletClient.t("Send to Notion", "Kirim ke Notion")
                        color: Theme.onPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onContainsMouseChanged: root.hint = containsMouse ? IsletClient.t("Send · Ctrl+Enter", "Kirim · Ctrl+Enter") : ""
                        onClicked: root.send()
                    }
                }
            }
        }

        // —— Reading ——
        Column {
            visible: !root.writing
            anchors.fill: parent
            spacing: 8

            // Drafts waiting on this computer (the notepad's tabs).
            Flow {
                visible: root.shownDrafts.length > 0
                width: parent.width
                spacing: 4
                HoverHandler {
                    id: draftHover
                }
                Repeater {
                    model: root.shownDrafts
                    Chip {
                        required property var modelData
                        text: "✎ " + root.tabTitle(modelData)
                        onClicked: root.show(NotepadStorageService.tabs.indexOf(modelData))
                    }
                }
            }

            Text {
                visible: root.error !== "" || (root.notes.length === 0)
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: root.error !== "" ? root.error : root.loading ? "Loading notes…" : "No notes yet"
                color: root.error !== "" ? Theme.error : Qt.alpha(Theme.onPrimaryContainer, 0.7)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            ListView {
                width: parent.width
                height: parent.height - y
                clip: true
                spacing: 8
                model: root.notes
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property bool open: root.openId === modelData.id
                    readonly property color bg: [Theme.primary, Theme.secondaryContainer, Theme.surfaceContainerHigh][index % 3]
                    readonly property color fg: index % 3 === 0 ? Theme.onPrimary : Theme.surfaceText
                    width: ListView.view.width
                    height: head.height + (open ? body.height + 10 : 0) + 20
                    radius: 14
                    color: bg
                    clip: true

                    Column {
                        id: head
                        x: 12
                        y: 10
                        width: parent.width - 24
                        spacing: 4
                        Row {
                            width: parent.width
                            Text {
                                width: parent.width - openBtn.width
                                text: card.modelData.title
                                textFormat: Text.PlainText
                                color: card.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeMedium
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                id: openBtn
                                text: "↗"
                                color: card.fg
                                font.pixelSize: Theme.fontSizeMedium
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openLink(card.modelData.url)
                                }
                            }
                        }
                        Flow {
                            width: parent.width
                            spacing: 4
                            visible: card.modelData.tipe !== "" || card.modelData.topik.length > 0
                            Repeater {
                                model: (card.modelData.tipe ? [card.modelData.tipe] : []).concat(card.modelData.topik)
                                Rectangle {
                                    required property string modelData
                                    width: chipText.implicitWidth + 12
                                    height: 20
                                    radius: 10
                                    color: Qt.alpha(card.fg, 0.15)
                                    Text {
                                        id: chipText
                                        anchors.centerIn: parent
                                        text: modelData
                                        textFormat: Text.PlainText
                                        color: card.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall - 2
                                    }
                                }
                            }
                        }
                    }

                    // The note itself, with its formatting.
                    Column {
                        id: body
                        visible: card.open
                        x: 12
                        anchors.top: head.bottom
                        anchors.topMargin: 10
                        width: parent.width - 24
                        spacing: 4
                        Text {
                            visible: root.openLoading
                            text: "…"
                            color: card.fg
                        }
                        Repeater {
                            model: card.open ? root.openLines : []
                            Text {
                                required property var modelData
                                width: body.width - leftPadding
                                leftPadding: modelData.depth * 14
                                textFormat: Text.StyledText
                                wrapMode: Text.WordWrap
                                linkColor: card.fg
                                onLinkActivated: link => root.openLink(link)
                                color: card.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: modelData.type.startsWith("heading") ? Theme.fontSizeLarge : Theme.fontSizeSmall
                                font.bold: modelData.type.startsWith("heading")
                                font.italic: modelData.type === "quote"
                                text: modelData.type === "bulleted_list_item" ? "•  " + modelData.html
                                    : modelData.type === "numbered_list_item" ? modelData.number + ".  " + modelData.html
                                    : modelData.type === "to_do" ? (modelData.checked ? "☑  <s>" + modelData.html + "</s>" : "☐  " + modelData.html)
                                    : modelData.type === "quote" ? "▍ " + modelData.html
                                    : modelData.type === "code" ? "<tt>" + modelData.html + "</tt>"
                                    : modelData.type === "divider" ? "───"
                                    : modelData.html
                            }
                        }
                        Text {
                            visible: card.open && root.openCut
                            width: body.width
                            wrapMode: Text.WordWrap
                            text: IsletClient.t("… a long note — open ↗ for the rest", "… catatan ini panjang — buka ↗ untuk sisanya")
                            color: Qt.alpha(card.fg, 0.7)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall - 1
                            font.italic: true
                        }
                    }

                    MouseArea {
                        anchors.fill: head
                        z: -1
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggle(card.modelData)
                    }
                }
            }
        }
    }
}
