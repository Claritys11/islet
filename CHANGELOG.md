# Changelog

## 1.6.0 — 2026-10-21

### Added
- **Hari ini**: a notch tab with today's lessons and close deadlines from your Notion timetable and task
  list (and Google Classroom). Tick a task to mark it Done, add one from the notch. Two-way sync with
  Google Calendar through Dank Calendar: lessons become weekly events, planned tasks become events; a
  change on either side follows to the other; conflicts are reported with a button to take the other
  version. The first sync shows a preview and waits for you. The pill announces a lesson 5 minutes ahead
  and deadlines due today; the notch opens to Hari ini each morning; nudges before deadlines.
  *Settings → Calendar & Notion*, `islet today`
- **Finder**: find files and folders from the notch, Listary-style. `Mod+G` / `islet find`, type part of a
  name (`isw` → islet-windows); Enter opens (folders in your file manager), Ctrl+T terminal there, Ctrl+E
  editor, Alt+Enter containing folder, Ctrl+C copy path. Projects and what you open often rank first.
  Its own index (fd + fzf), refreshed every 10 minutes, skipping junk like `node_modules`, `venv` and Go's
  module cache. *Settings → Finder*, and `islet find --bind` sets up the niri shortcut

## 1.5.0 — 2026-10-21

### Added
- **Setup guide** on first start (and `islet setup`): where you play music, bar or floating island, lyrics on
  the screen edge, and a look — every answer applies right away
- **Search in Settings**: plain words (*youtube*, *too fast*, *weather*) give an answer and jump to the
  setting, which lights up. `islet settings <words>` opens Settings searching; `islet settings weatherCity`
  goes straight to a setting
- **Test mode switch** (sample lyrics) in the Settings sidebar, on every page, and *Start with sample lyrics
  when nothing plays*
- Notch **pin** (📌): stays open after the mouse leaves. The Shelf tab and file drags keep it open too, so
  dragging files in works. *Close after* delay setting (default 1.2 s, was 0.45 s)

## 1.4.0 — 2026-10-21

### Added
- **YouTube Music, YouTube and other players**: Islet follows whatever is playing (the *Preferred player*
  setting wins when several are) and keeps the last one when you pause. Video titles are tidied before
  searching LRCLIB: *Artist - Song (Official Video)*, *ArtistVEVO*, *Artist - Topic*, K-pop *'Song' MV*,
  and artists joined in your language (*Lady Gaga dan Bruno Mars*)
- **File shelf**: a Shelf tab in the notch. Drop files on the island or on the DMS pill, drag them out into
  any app, click to open. `islet shelf FILE…`
- **Visualizer mode**: while you're away and music plays, the notch becomes a 24-bar visualizer
  (*Settings → Notch*; `islet notch viz`)
- **Weather** in the pill and DMS bar widget when nothing plays (Open-Meteo; your city or DMS's location)
- **Break tips** in the Focus tab and the break notification
- **Share card**: a 1080×1080 image of the song and a lyric line, copied or saved (`islet share [copy|save]`)
- *Smoothness* setting (30 / 60 / 120 fps) and `islet notch status`

### Changed
- **Much lighter while music plays**: about 15 % of one CPU core instead of 50 % on a 180 Hz screen, and the
  DMS bar widget no longer keeps DankMaterialShell redrawing (7 % instead of 28 %). The lyrics wheel moves
  only the rows on screen and sets the scroll once per frame, font weight blends in steps, the clock runs at
  the chosen frame rate, visualizer bars are no longer rebuilt on every update, and hidden parts of the notch
  stop animating

## 1.3.1 — 2026-10-20

### Added
- Focus: reset only the pause time (↻ next to "paused" in the Focus tab, *Reset pause time* in
  Settings, or `islet pomodoro resetpause`) — the timer and the rest of the session stay as they are

## 1.3.0 — 2026-10-19

### Added
- Focus: **continuous mode** (∞ button in the Focus tab) — focus and breaks roll on by themselves
- Focus: session stats — time elapsed since you started, time actually focused and time paused — and
  the minutes focused today
- **Easy updates**: Islet checks for new versions (every 6 h, can be turned off), notifies you once, and
  Settings shows what's new with an *Update now* button. `islet update` now also refreshes links, the DMS
  bar widget and the Spicy Lyrics bridge, and refuses to clobber local edits; `islet update --check`
  only shows what's new
- Focus: a pause clock that counts up while paused, a pause icon in the DMS pill, and a reminder when a
  pause runs long (*Pause reminder*, 10 min by default, 0 turns it off)

### Fixed
- The notch (and the settings toast) vanished for good after the monitor slept or was unplugged, so
  clicking the DMS pill did nothing until Islet was restarted. They're now rebuilt when the screen
  comes back.

## 1.2.0 — 2026-10-18

### Added
- **DankMaterialShell bar widget**: `islet dms` installs the *Islet Media* DMS plugin in place of DMS's
  media widget — artwork, the lyric being sung with karaoke fill, visualizer and focus timer in a native
  DMS pill. Left click drops Islet's island right under it; right click plays/pauses.
- Notch *bar mode*: no floating pill; the island opens as a dropdown at the bar widget and tidies itself
  away if you don't move into it
- `IsletLink`: Islet's state as JSON lines over `$XDG_RUNTIME_DIR/islet.sock`, plus commands, so any
  shell can show Islet

### Fixed
- Spicy Lyrics lines no longer carry invisible zero-width spaces

## 1.1.1 — 2026-10-18

### Fixed
- Lyrics now **scroll** from line to line on a smooth spring instead of blinking: the wheel position was
  bound to the current line, so it jumped instantly and the animation never ran
- Rows could overlap (wrapped lines, background vocals) after the lyrics were reloaded: row heights are
  now read from the rows themselves instead of reports that could be lost
- Lyrics re-sent by the Spicy Lyrics bridge no longer rebuild every line (a visible flash every 15 s)
- The active line's font weight blends in instead of snapping, and the glow layer is prepared before a
  line becomes active

## 1.1.0 — 2026-10-18

### Added
- **Spicy Lyrics integration**: `islet spicetify` installs the Islet Bridge Spicetify extension, which
  shares the syllable-synced lyrics Spicy Lyrics already loaded and Spotify's own playback position with
  Islet over localhost. The karaoke fill follows every syllable, background vocals included.
- *Lyrics from* setting (Spicy Lyrics with LRCLIB fallback, or LRCLIB only) with a live connection status,
  and a separate timing offset for Spicy Lyrics (+100 ms, like Spicy Lyrics itself)

### Changed
- The playback clock uses Spicy Lyrics' smoothing: real jumps snap, small jitter is pulled in with a
  300 ms time constant, so lyrics never stutter or drift

## 1.0.0 — 2026-10-18

First release as **Islet** (previously *lyrics-wheel*).

### Added
- **Notch**: a dynamic island with live-activity pill, hover peek, and Media / Focus / Checklist tabs
- **Focus**: Pomodoro timer with auto-advancing breaks, notifications and a daily count
- **Checklist**: local tasks, or synced with the to-dos of a Notion page
- **Settings window** with per-module pages, change markers, one-click resets, an on-screen toast for
  every change, live notch preview and sample lyrics
- Lyrics: balanced line wrapping, background vocals with their own timing, visible-area controls with
  soft edges, LRCLIB version picker
- Karaoke fill follows each song's own singing pace (measured from the lyric timestamps), with a
  *Fill speed* adjustment
- One-line installer, `islet` CLI (`settings`, `set`, `get`, `notch`, `pomodoro`, `todo`, `update`…),
  systemd user service, launcher entry, Arch PKGBUILD, instructions for AI agents

### Fixed
- Lyrics drifting ahead of the song: the fill used a fixed pace that was too fast for most songs
- Picking the wrong LRCLIB version (different recording or broken upload) when the track length
  wasn't known yet
- Pill lyrics in the notch are cut off and follow the singer instead of ending in "…"

## 0.1.0

Initial release as *lyrics-wheel*: OptionWheel-style synced lyrics with karaoke glow.
