# Contributing

Thanks for helping! Islet is plain QML on [Quickshell](https://quickshell.org) — no build step.

## Develop

```sh
git clone https://github.com/Claritys11/islet && cd islet
./install.sh            # links your clone, so edits apply live
islet restart           # or just save a .qml file: Quickshell hot-reloads
journalctl --user -u islet -f
```

To try things without touching your own settings, point Islet at throwaway folders:

```sh
ISLET_CONFIG_DIR=/tmp/islet-cfg ISLET_STATE_DIR=/tmp/islet-state qs -p .
```

## Layout

| File | |
|---|---|
| `shell.qml` | Windows, IPC handlers, live-preview wiring |
| `Config.qml` / `Store.qml` | Settings and app data |
| `LyricsService.qml` | MPRIS, LRCLIB, LRC parsing, karaoke timing |
| `LyricsWheel.qml`, `SweepText.qml`, `SweepLine.qml` | Lyrics overlay |
| `NotchIsland.qml`, `NotchWindow.qml`, `Notch*.qml` | Notch |
| `PomodoroService.qml`, `ChecklistService.qml`, `CavaService.qml`, `Theme.qml` | Services |
| `SettingsWindow.qml` | Settings |
| `Showcase.qml`, `tools/make-media.sh` | README screenshots and GIF |

## Screenshots and GIF

Media in `docs/media/` is rendered from the real components on a mock desktop (never a real screen):

```sh
./tools/make-media.sh    # needs ffmpeg and imagemagick; takes ~1 minute
```

A 1280×720 scene appears in the middle of your screen while it renders; it doesn't take input.

## Guidelines

- Match the surrounding code: QML formatted like `qmlformat`, comments explain *why*.
- Every new setting goes in `Config.qml` (`defaults` + `JsonAdapter`), gets a row in
  `SettingsWindow.qml`, and a line in the README table.
- Test with music playing *and* with nothing playing (sample lyrics).
