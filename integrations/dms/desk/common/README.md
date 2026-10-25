# Islet desktop widgets — shared code

Used by every widget in `integrations/dms/desk/*` (each has a `common → ../common` symlink and imports
it as `import "common"`; Quickshell doesn't load `..` imports reliably). Not a plugin itself.

| File | What |
|---|---|
| `IsletClient.qml` | One connection to `$XDG_RUNTIME_DIR/islet.sock`: state slices, `send`, `request`/`cancel` |
| `Requester.qml` | `request` for one widget; cancels what's left when the widget goes |
| `DeskCard.qml`, `DeskStyle.qml`, `Glass.qml`, `style.mjs` | The card; solid/glass look shared by all (DMS `plugin_settings.json` → `deskwStyle`); compositor blur |
| `StyleSettings.qml` | The shared look's settings, on every widget's settings page |
| `FormatBar.qml`, `fmtkeys.mjs`, `mdedit.mjs` | Markdown toolbar and shortcuts (Notes widget and the patched DMS notepad) |
| `rich.mjs` | Notion blocks → StyledText, safe links, Notion app links, month grid |
| `slices.mjs` | Islet's state line cut into the parts widgets draw |
| `CookieShape.qml`, `cookie.mjs` | The clock's wavy cookie |

Protocol: the comment at the top of `IsletLink.qml`. QML's JavaScript engine lacks some newer
built-ins (e.g. `String.prototype.matchAll`), so keep `.mjs` code to what it has.

Tests (from the repo root): `node --test tests/*.test.mjs` (the `desk-*` ones), `sh tests/desk-load.sh`.
