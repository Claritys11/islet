# 🏝️ Islet

A little island of extras for your Linux desktop: **synced karaoke lyrics**, a **dynamic-island notch**
with music controls, a **Pomodoro** timer and a **checklist** (local or synced with Notion).

Built with [Quickshell](https://quickshell.org), so it sits naturally next to
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) on [niri](https://github.com/YaLTeR/niri)
— and works on any compositor with wlr-layer-shell (Hyprland, Sway, river, …).
Every module can be turned on or off on its own.

## Modules

### 🎤 Lyrics overlay

- Synced lyrics from [LRCLIB](https://lrclib.net) for Spotify or any MPRIS player — no API keys, no Spicetify extension
- Curved wheel inspired by [React Bits' OptionWheel](https://reactbits.dev/components/option-wheel), visible on **every workspace**
- **Karaoke fill** — soft sweep or typewriter reveal with **neon glow** (like [Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics))
- **Background vocals** `( … )` shown smaller under the line, and they keep glowing while they're still being sung
- **Long lines wrap** onto balanced rows, with the fill carried through them
- **Visible area** — set width, height and position; lines fade out softly at the edges instead of being cut
- **Lyrics version picker** — when LRCLIB has several versions (album, live, radio edit), pick the one that matches

### 🏝️ Notch

Inspired by [Notchy](https://notchy.dev) for macOS:

- **Pill** shows live activities side by side: artwork + current lyric + audio visualizer, and the running timer
- **Hover** for a now-playing peek, **click** for the full island with **Media**, **Focus** and **Checklist** tabs
- Follows your DankMaterialShell / Matugen colours (or pure black), springy animations
- Real audio spectrum when [`cava`](https://github.com/karlstav/cava) is installed (`pacman -S cava`)

### ⏱️ Focus

Pomodoro with focus / short / long breaks, auto-advance, notifications, sound and a daily session count.

### ✅ Checklist

Tasks saved on your computer, or synced with the to-do blocks of a **Notion** page.

## Install

Requires `quickshell` (already installed if you use DMS; otherwise `pacman -S quickshell`).

```sh
git clone https://github.com/Claritys11/islet.git ~/.local/src/islet
~/.local/src/islet/install.sh --enable
```

That links the config into `~/.config/quickshell/islet`, adds the `islet` command, an
**"Islet Settings"** entry in your app launcher, and a systemd user service that starts Islet with your
session (just like `dms.service`). Drop `--enable` to start it yourself instead.

Update with `git pull`. Remove with `./uninstall.sh`.

> **Coming from lyrics-wheel?** Run `./install.sh` again: it removes the old install, and your
> settings, tasks and Notion secret are carried over on first start.

## Settings

Open **Islet Settings** from your launcher, or `islet settings`. Everything applies live, and Islet
shows you what you changed:

- a toast on screen names each change and its new value
- changed settings get a dot and a one-click reset; the sidebar counts changes per module
- the lyrics area is outlined on screen while settings are open, and sample lyrics play when nothing else is
- notch size changes open the notch so you can see them

Settings are stored in `~/.config/islet/config.json` (hand edits reload live too).
Tasks and focus history live in `~/.local/state/islet/state.json`.

## Command line

```
islet settings [overview|lyrics|notch|focus|checklist|about]
islet set <key> <value>        e.g. islet set glow 0.9
islet get <key>
islet toggle | show | hide     the lyrics overlay
islet refetch                  re-download lyrics for this song
islet status
islet notch [media|focus|checklist]
islet pomodoro [toggle|reset|skip|status]
islet todo "Buy milk"          add a task (no text = list tasks)
islet start | stop | restart
```

### niri

```kdl
binds {
    Mod+Shift+L { spawn "islet" "toggle"; }
    Mod+Ctrl+L  { spawn "islet" "settings"; }
    Mod+N       { spawn "islet" "notch"; }
    Mod+Alt+P   { spawn "islet" "pomodoro" "toggle"; }
}

// Open the settings window floating instead of as a tile.
window-rule {
    match title="^Islet Settings$"
    open-floating true
}
```

If you didn't enable the systemd service, autostart with `spawn-at-startup "islet" "start"`.

### Hyprland

```
bind = SUPER SHIFT, L, exec, islet toggle
windowrulev2 = float, title:^(Islet Settings)$
```

## Notion checklist

1. Create an integration at [notion.so/profile/integrations](https://www.notion.so/profile/integrations) and copy its **Internal Integration Secret**.
2. Open the Notion page that holds your checklist → **•••** → **Connections** → add your integration.
3. In **Settings → Checklist**, choose *Notion*, paste the secret and the page link, and press **Test connection**.

Every to-do block on that page shows up in the notch; ticking, adding and deleting sync back to Notion.
The secret is stored only in `~/.config/islet/notion-token` (mode 600).

## Troubleshooting

- **Lyrics out of sync** — LRCLIB often has several versions of a song. Open *Settings → Lyrics →
  Lyrics version for this song*, press **Find versions** and pick one whose length is shown in green.
  For a constant delay, use *Timing offset*.
- **"No lyrics found"** — LRCLIB doesn't have the song yet. You can add it at [lrclib.net](https://lrclib.net).
- **"Couldn't reach LRCLIB"** — the free server is sometimes busy; Islet retries automatically.
- **Nothing shows** — check `islet status` and `journalctl --user -u islet`, and that your player appears in `playerctl -l`.

## How it works

| File | |
|---|---|
| `shell.qml` | Windows (lyrics per monitor, notch, toast), IPC handlers, live-preview wiring |
| `Config.qml` / `Store.qml` | Settings (`config.json`) and app data (`state.json`) via `FileView` + `JsonAdapter` |
| `LyricsService.qml` | MPRIS tracking, LRCLIB fetching with retry + version scoring, LRC parsing, karaoke and background-vocal timing |
| `LyricsWheel.qml` | QML port of the OptionWheel layout with variable row heights. Lyric layer surfaces belong to the output, not a workspace — that's why they stay visible everywhere |
| `SweepText.qml` / `SweepLine.qml` | Balanced wrapping; karaoke fill through a moving gradient mask with glow |
| `NotchWindow.qml` + `Notch*.qml` | The notch and its tabs |
| `PomodoroService.qml`, `ChecklistService.qml`, `CavaService.qml` | Focus timer, local/Notion checklist, audio spectrum |
| `Theme.qml` | Reads DMS's Matugen palette |
| `SettingsWindow.qml` | Settings |

## Credits

Wheel layout from [React Bits](https://reactbits.dev) (MIT). Karaoke look inspired by
[Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics). Notch inspired by [Notchy](https://notchy.dev).
Lyrics by the [LRCLIB](https://lrclib.net) community.

## License

[MIT](LICENSE)
