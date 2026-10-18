# 🎤 lyrics-wheel

Synced, karaoke-style lyrics floating on the edge of your screen — on **every workspace**.
The current line glows and fills as it's sung (like [Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics)),
on a curved wheel inspired by [React Bits' OptionWheel](https://reactbits.dev/components/option-wheel).

Built with [Quickshell](https://quickshell.org), so it sits naturally next to
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) on [niri](https://github.com/YaLTeR/niri)
— and works on any compositor with wlr-layer-shell (Hyprland, Sway, river, …).

## Features

- **Follows Spotify** (or any MPRIS player) — no API keys, no Spicetify extension required
- **Synced lyrics** from [LRCLIB](https://lrclib.net), the free & open lyrics database, with fuzzy fallback search
- **Karaoke fill** — a soft sweep or a typewriter reveal through the current line, with **neon glow**
- **Background vocals** — `(…)` parts are shown smaller, dimmer and italic under the main line
- **Word-level timing** when the lyrics have it (enhanced LRC), estimated otherwise
- **Settings panel** with presets (Spicy · Neon · Cyber · Typewriter · Minimal) and live preview
- Visible on every workspace, click-through, multi-monitor, left or right edge

## Install

Requires `quickshell` (already installed if you use DMS; otherwise `pacman -S quickshell`).

```sh
git clone https://github.com/Claritys11/lyrics-wheel.git ~/.local/src/lyrics-wheel
~/.local/src/lyrics-wheel/install.sh --enable
```

That links the config into `~/.config/quickshell/lyrics-wheel`, adds the `lyrics-wheel` command,
a **"Lyrics Wheel Settings"** entry in your app launcher, and a systemd user service that starts it
with your session (just like `dms.service`). Drop `--enable` to start it yourself instead.

Update with `git pull` — your settings live separately in `~/.config/lyrics-wheel/config.json`.
Remove with `./uninstall.sh`.

## Usage

```
lyrics-wheel settings   open the settings panel
lyrics-wheel toggle     show / hide the lyrics
lyrics-wheel show|hide
lyrics-wheel refetch    re-download lyrics for the current song
lyrics-wheel status     what's playing + lyrics status
lyrics-wheel start|stop|restart
```

### niri

Add to `~/.config/niri/config.kdl`:

```kdl
binds {
    Mod+Shift+L { spawn "lyrics-wheel" "toggle"; }
    Mod+Ctrl+L  { spawn "lyrics-wheel" "settings"; }
}

// Open the settings panel as a floating window instead of a tile.
window-rule {
    match title="^Lyrics Wheel"
    open-floating true
}
```

If you didn't use the systemd service, autostart with `spawn-at-startup "lyrics-wheel" "start"`.

### DankMaterialShell

Search **"Lyrics Wheel Settings"** in the DMS launcher. Lyrics appear above windows by default;
pick *Behind windows* in **Settings → Placement → Layer** to show them only on your wallpaper.

### Other compositors

Hyprland: `bind = SUPER SHIFT, L, exec, lyrics-wheel toggle` and
`windowrulev2 = float, title:^(Lyrics Wheel)`.

## Configuration

Everything is in the settings panel. You can also edit `~/.config/lyrics-wheel/config.json`
by hand — it reloads live.

| Key | Default | Description |
|---|---|---|
| `player` | `"spotify"` | MPRIS player to follow; `""` = any |
| `offsetMs` | `250` | Timing shift; positive shows lines earlier |
| `lrclibUrl` | `"https://lrclib.net"` | LRCLIB server |
| `side` | `"right"` | `"right"` or `"left"` |
| `screens` | `""` | Comma-separated monitor names (`niri msg outputs`); empty = all |
| `layer` | `"top"` | `"top"` above windows, `"overlay"` above everything, `"bottom"` behind windows |
| `clickThrough` | `true` | `false` lets you click a line to seek to it |
| `width`, `inset` | `620`, `80` | Panel width, and gap between screen edge and lyrics (px) |
| `marginTop`, `marginBottom`, `marginSide` | `60`, `60`, `0` | Panel margins (px) |
| `karaoke` | `"sweep"` | `"sweep"`, `"typewriter"` or `"none"` |
| `unsungOpacity` | `0.45` | Opacity of the not-yet-sung part of the line |
| `feather` | `28` | Softness of the sweep edge (px) |
| `glow`, `glowColor` | `0.7`, `"#ffffff"` | Neon glow strength (0–1) and colour |
| `bgVocals` | `"below"` | `(…)` vocals: `"below"`, `"same"` or `"hidden"` |
| `bgScale`, `bgOpacity`, `bgItalic` | `0.62`, `0.7`, `true` | Background vocal styling |
| `activeColor`, `textColor` | `"#ffffff"`, `"#a6a6a6"` | Active line / other lines |
| `fontFamily`, `fontSize`, `minFontSize` | `"Google Sans Flex"`, `30`, `14` | Long lines shrink toward `minFontSize` |
| `restingWeight`, `activeWeight` | `200`, `500` | Font weights (100–900) |
| `spacing`, `curve`, `tilt` | `1.5`, `1`, `6` | Wheel shape — row spacing × font size, curve depth, degrees per line |
| `blur`, `fade`, `minOpacity` | `2`, `0.25`, `0.05` | Per-line blur (px) and opacity falloff |
| `smoothing`, `visibleLines` | `200`, `6` | Scroll easing (ms), lines drawn around the active one |
| `shadow`, `backdrop`, `showTrackInfo` | `true`, `0.35`, `true` | Readability |
| `hideWhenPaused`, `hideWhenNoLyrics`, `fadeDuration` | `false`, `false`, `400` | Auto-hide |

## How it works

| File | |
|---|---|
| `shell.qml` | One layer-shell panel per monitor + IPC handler. Layer surfaces belong to the output, not a workspace — that's why lyrics stay visible everywhere |
| `LyricsService.qml` | Tracks the player over MPRIS, fetches from LRCLIB, parses LRC, splits background vocals, computes karaoke progress |
| `LyricsWheel.qml` | QML port of the OptionWheel layout, with variable row heights |
| `SweepText.qml` | Karaoke text: dim base + bright glowing copy revealed through a moving gradient mask |
| `SettingsWindow.qml` | The settings panel |
| `Config.qml` | Defaults + `config.json` binding (`FileView` + `JsonAdapter`) |

## Troubleshooting

- **"No lyrics found"** — LRCLIB doesn't have the song yet. You can add it at [lrclib.net](https://lrclib.net); everyone benefits.
- **Lines are early/late** — adjust *Settings → Lyrics → Timing offset*.
- **Nothing shows** — check `lyrics-wheel status` and `journalctl --user -u lyrics-wheel`.
  Make sure the player shows up in `playerctl -l`.

## Credits

Wheel layout from [React Bits](https://reactbits.dev) (MIT). Karaoke look inspired by
[Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics). Lyrics by the [LRCLIB](https://lrclib.net) community.

## License

[MIT](LICENSE)
