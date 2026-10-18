<div align="center">

# 🏝️ Islet

### The open-source Notchy alternative for Linux

A dynamic-island notch, synced karaoke lyrics, a Pomodoro timer and a Notion checklist —
for niri, Hyprland, Sway, KDE Plasma and any Wayland compositor with layer-shell.

[![License: MIT](https://img.shields.io/badge/license-MIT-a8c7fa?style=flat-square)](LICENSE)
[![Built with Quickshell](https://img.shields.io/badge/built%20with-Quickshell-7c5cff?style=flat-square)](https://quickshell.org)
[![Wayland](https://img.shields.io/badge/Wayland-layer--shell-3ee6ff?style=flat-square)](#-requirements)
[![DankMaterialShell](https://img.shields.io/badge/works%20with-DankMaterialShell-ff4fd8?style=flat-square)](https://github.com/AvengeMedia/DankMaterialShell)

<img src="docs/media/demo.gif" alt="Islet: the notch pill showing the current lyric and a running focus timer, with glowing karaoke lyrics on the right edge of the screen" width="880">

**[Install](#-install) · [Features](#-features) · [Ask your AI agent](#-let-your-ai-agent-install-it) · [Settings](#-settings) · [FAQ](#-faq)**

</div>

---

## ⚡ Install

```sh
curl -fsSL https://raw.githubusercontent.com/Claritys11/islet/main/install.sh | sh
```

That's it — Islet starts right away and with every login. No sudo, no build step, nothing touched
outside your home folder. Open **Islet Settings** from your app launcher to make it yours.

<details>
<summary>Other ways to install</summary>

**From a clone** (good for hacking on it — edits apply live):

```sh
git clone https://github.com/Claritys11/islet ~/.local/src/islet
~/.local/src/islet/install.sh --enable
```

**Arch / CachyOS (PKGBUILD)**: `cd packaging/arch && makepkg -si`, then
`systemctl --user enable --now islet`.

**Update**: `islet update` · **Uninstall**: `~/.local/share/islet/uninstall.sh`

</details>

### 🤖 Let your AI agent install it

Using Claude Code, Codex, Cursor or another coding agent? Paste this:

> Install Islet from https://github.com/Claritys11/islet by following its AGENTS.md. Check my system
> first, verify it's running at the end, and ask me before adding keybinds to my compositor config.

[`AGENTS.md`](AGENTS.md) gives the agent exact, verifiable steps — requirements per distro, install,
health checks, and keybinds for niri, Hyprland and Sway.

### 📋 Requirements

| | |
|---|---|
| **Desktop** | Wayland with layer-shell: **niri, Hyprland, Sway, KDE Plasma, river, Wayfire, labwc** |
| **Quickshell** | 0.2 or newer — `pacman -S quickshell` (already there if you use DankMaterialShell) |
| **Music** | Spotify desktop or any [MPRIS](https://specifications.freedesktop.org/mpris-spec/latest/) player (browsers, mpv, Tidal-hifi, …) |
| Optional | [`cava`](https://github.com/karlstav/cava) for a real audio visualizer |

> **Windows, macOS, GNOME?** Islet is built on Quickshell, which only runs on Linux Wayland compositors
> that support layer-shell — GNOME, X11, Windows and macOS can't host it. On macOS, try
> [Notchy](https://notchy.dev) itself.

---

## ✨ Features

### 🏝️ The notch

A dynamic island at the top of your screen, in the spirit of [Notchy](https://notchy.dev).

| Live activities | Hover to peek |
|:---:|:---:|
| <img src="docs/media/notch-pill.png" width="420" alt="Notch pill with artwork, current lyric, visualizer and focus timer"> | <img src="docs/media/notch-peek.png" width="420" alt="Notch hover peek with artwork, title, progress and controls"> |
| Artwork, the line being sung, an audio visualizer and your timer — side by side | Now playing with play/pause and skip, without opening anything |

| 🎵 Media | ⏱️ Focus | ✅ Checklist |
|:---:|:---:|:---:|
| <img src="docs/media/notch-media.png" width="300" alt="Media tab"> | <img src="docs/media/notch-focus.png" width="300" alt="Focus tab"> | <img src="docs/media/notch-checklist.png" width="300" alt="Checklist tab"> |
| Scrubber, shuffle, repeat, and the current lyric with karaoke fill | Pomodoro with short & long breaks, notifications and a daily count | Saved on your computer — or **synced with a Notion page** |

Click the pill to open it. It follows your DankMaterialShell / Matugen wallpaper colours, or stays pure black.

### 🎤 Karaoke lyrics, everywhere

<img src="docs/media/hero.png" alt="Islet on a desktop: notch at the top, glowing lyrics wheel on the right" width="100%">

- **Synced lyrics** for whatever is playing, from the free and open [LRCLIB](https://lrclib.net) — no API keys needed
- **🌶️ Spicy Lyrics timing** — already using [Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics)? One command makes Islet show the *same* syllable-by-syllable lyrics, on Spotify's exact clock ([details](#-spicy-lyrics-integration))
- **Visible on every workspace** — it lives on the screen, not on a workspace
- **Karaoke fill** that glows as each line is sung (sweep or typewriter), inspired by [Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics)
- **Follows the singer**: the fill speed is measured from each song's own timing, so ballads and rap both feel right
- **Background vocals** `( … )` appear smaller under the line, and keep glowing while they're still being sung
- **Long lines wrap** into balanced rows; the curved wheel is a port of [React Bits' OptionWheel](https://reactbits.dev/components/option-wheel)
- **Your area, your edges** — choose width, height and position; lines fade out softly instead of being cut
- **Right version, right timing** — when LRCLIB has several versions (album, live, radio edit), Islet picks the one matching your song, and you can switch with one click

### 🧩 Settings

<img src="docs/media/settings.png" alt="Islet settings window: sidebar of modules with change badges, Lyrics page with presets and sliders" width="760">

Everything is live, and Islet shows you exactly what you changed:

- **A toast on screen** names every change and its new value
- **Changed settings** are marked, with a one-click reset; the sidebar counts changes per module
- **See it while you tune it** — the lyrics area is outlined on screen, sample lyrics play when nothing
  else is, and notch size changes open the notch
- **Presets**: Spicy · Neon · Cyber · Typewriter · Minimal

Prefer the terminal? `islet set glow 0.9`, `islet get offsetMs`. Settings live in
`~/.config/islet/config.json` (hand edits reload instantly).

---

## ⌨️ Command line & keybinds

```
islet settings [lyrics|notch|focus|checklist]    open settings (on a page)
islet notch [media|focus|checklist]             toggle the notch / open a tab
islet toggle | show | hide                      the lyrics overlay
islet pomodoro [toggle|reset|skip|status]
islet todo "Buy milk"                           add a task (no text = list them)
islet set <key> <value> · islet get <key>
islet spicetify [install|uninstall|status]      Spicy Lyrics lyrics & timing
islet status · islet refetch · islet update · islet start|stop|restart
```

<details>
<summary><b>niri</b></summary>

```kdl
binds {
    Mod+Shift+L { spawn "islet" "toggle"; }
    Mod+Ctrl+L  { spawn "islet" "settings"; }
    Mod+N       { spawn "islet" "notch"; }
    Mod+Alt+P   { spawn "islet" "pomodoro" "toggle"; }
}

window-rule {
    match title="^Islet Settings$"
    open-floating true
}
```
</details>

<details>
<summary><b>Hyprland</b></summary>

```
bind = SUPER SHIFT, L, exec, islet toggle
bind = SUPER, N, exec, islet notch
bind = SUPER ALT, P, exec, islet pomodoro toggle
windowrulev2 = float, title:^(Islet Settings)$
```
</details>

<details>
<summary><b>Sway</b></summary>

```
bindsym $mod+Shift+l exec islet toggle
bindsym $mod+n exec islet notch
for_window [title="^Islet Settings$"] floating enable
```
</details>

<details>
<summary><b>KDE Plasma</b></summary>

System Settings → Keyboard → Shortcuts → **Add New → Command or Script**, e.g. `islet notch`.
</details>

---

## 🌶 Spicy Lyrics integration

[Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics) looks perfectly in time because it has
**syllable-synced lyrics** and reads **Spotify's own playback clock** from inside the app. If you use it
with [Spicetify](https://spicetify.app), Islet can use exactly the same:

```sh
islet spicetify      # installs the Islet Bridge extension and runs `spicetify apply` (Spotify restarts)
```

The small **Islet Bridge** extension reads the lyrics Spicy Lyrics has *already* loaded and samples the
playback position the same way Spicy Lyrics does, then hands both to Islet on `127.0.0.1`. It never
contacts Spicy Lyrics' servers itself, and nothing leaves your computer. Islet applies Spicy Lyrics'
clock smoothing and +100 ms latency lead, so the glow fills each syllable as it's sung — background vocals
included.

Songs Spicy Lyrics doesn't have fall back to LRCLIB automatically. See the status under
**Settings → Lyrics → Source & timing**, or run `islet spicetify status`. Requires `python3` (used for the
tiny local receiver). Remove with `islet spicetify uninstall`.

## 📝 Notion checklist

1. Create an integration at [notion.so/profile/integrations](https://www.notion.so/profile/integrations) and copy its **Internal Integration Secret**.
2. Open the Notion page with your checklist → **•••** → **Connections** → add the integration.
3. In **Islet Settings → Checklist**, choose **Notion**, paste the secret and the page link, press **Test connection**.

Every to-do block on that page appears in the notch; ticking, adding and deleting sync back. The secret
stays on your computer (`~/.config/islet/notion-token`, readable only by you).

---

## 🍏 Coming from Notchy?

Islet is young and focused. Here's what carries over today:

| Notchy | Islet |
|---|---|
| Live activities on the closed notch | ✅ Music + lyric + visualizer, focus timer |
| Hover peek, click to open | ✅ |
| Media controls, scrubbing, shuffle, repeat | ✅ |
| Time-synced lyrics via LRCLIB | ✅ Plus syllable-synced lyrics from Spicy Lyrics, and a karaoke overlay on the screen edge |
| Audio spectrum visualizer | ✅ via cava |
| Pomodoro focus sessions | ✅ |
| Quick notes / reminders | ✅ Checklist, local or Notion |
| Notch or pill shape, adjustable size | ✅ |
| Clipboard history, file shelf, HUDs, weather, calendar… | 🔜 Not yet — [ideas welcome](https://github.com/Claritys11/islet/issues/new?template=feature_request.yml) |

---

## ❓ FAQ

<details>
<summary><b>Lyrics are out of sync</b></summary>

Using Spotify with Spicetify + Spicy Lyrics? Run `islet spicetify` — Islet then uses Spicy Lyrics'
syllable timing and Spotify's own clock. Otherwise: LRCLIB often has several versions of a song. Open **Settings → Lyrics → Lyrics version for this song**,
press **Find versions** and pick one whose length shows in green. If the *fill* runs ahead or behind the
singer, adjust **Fill speed**; for a constant delay, use **Timing offset**.
</details>

<details>
<summary><b>"No lyrics found"</b></summary>

LRCLIB doesn't have the song yet — you can add it at [lrclib.net](https://lrclib.net) and everyone benefits.
"Couldn't reach LRCLIB" means the free server is busy; Islet retries by itself.
</details>

<details>
<summary><b>Nothing shows up</b></summary>

Run `islet status` and `journalctl --user -u islet -n 50`. Check your player appears in `playerctl -l`,
and that your desktop supports layer-shell (GNOME doesn't).
</details>

<details>
<summary><b>Does it slow my computer down?</b></summary>

Islet renders only what's visible and idles when nothing plays. The visualizer runs only while music is playing.
</details>

<details>
<summary><b>I used lyrics-wheel</b></summary>

That was Islet's old name. Run the installer again: it removes the old install and your settings,
tasks and Notion secret come along automatically.
</details>

---

## 🤝 Contributing

Islet is plain QML — no build step, hot reload on save. See [CONTRIBUTING.md](CONTRIBUTING.md).
The screenshots and GIF above are rendered from the real components with `tools/make-media.sh`.

## 💜 Credits

Curved wheel from [React Bits](https://reactbits.dev) (MIT) · karaoke look inspired by
[Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics) · notch inspired by [Notchy](https://notchy.dev) ·
lyrics by the [LRCLIB](https://lrclib.net) community · built on [Quickshell](https://quickshell.org).

[MIT License](LICENSE)
