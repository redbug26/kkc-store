# KKC Kapsule API reference

[Development guide](lua-applications.md) · [Callbacks](#callbacks) ·
[Modules](#modules) · [Conventions](#conventions)

## Conventions

- Import modules with `local gfx = require("kkc-graphics")`.
- Call module functions with dot syntax: `gfx.clear()`.
- `?` marks an optional argument. `→` lists return values; omitted returns mean no useful value.
- Lua sequences and drawing coordinates start at 1. Colors are integers in `0xRRGGBB` format.
- Drawing uses character cells, not pixels. Positions are integer columns and rows.
- Filesystem, process, dialog, and audio failures can raise Lua errors. Use `pcall` for recoverable operations.

## Callbacks

Return a table from the entry script. A global `app` table is also accepted
when no table is returned. All callbacks are optional; their return values
are ignored except for `shortcuts`.

```lua
local app = {}
function app.draw()
    require("kkc-graphics").text(1, 1, "Hello")
end
return app
```

### Initialization and frames

| Callback | Arguments | When called |
| --- | --- | --- |
| `app.init(ctx)` | Context table below. | Once after the entry script loads, before window setup. |
| `app.resize(w, h)` | Integer content width and height. | Initial window setup, terminal resize, and F5 zoom changes. |
| `app.update(dt)` | Number of elapsed seconds. | Each frame before drawing. |
| `app.draw()` | None. | Each frame after updating. |
| `app.shortcuts()` | None. Returns an array of strings. | Each frame before host rendering. |

`ctx` fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Manifest application ID. |
| `name` | string | Display name, defaulting to ID. |
| `version` | string | Version, defaulting to `"0.1.0"`. |
| `description` | string | Description, defaulting to `""`. |
| `width`, `height` | integers | Initial terminal dimensions; use subsequent `resize` for content dimensions. |
| `args` | array of strings | Expanded launcher arguments, indexed from 1. |

`shortcuts()` returns labels such as `{ "Enter:Start", "Esc:Quit" }`. The host
splits each label at its first colon and draws a native shortcut bar on the
last content row. Labels do not bind keys: implement the corresponding key
callbacks. An empty list hides the bar.

### Keyboard and focus

| Callback | Meaning |
| --- | --- |
| `app.keydown(key)` | A newly detected press. |
| `app.keypressed(key)` | Press or repeat event. |
| `app.keyup(key)` | Release event, when the terminal reports releases. |
| `app.focuslost()` | Terminal loses focus; host clears held keys. |
| `app.focusgained()` | Terminal regains focus. |

Key names: `left`, `right`, `up`, `down`, `space`, `enter`, `esc`, `backspace`,
`delete`, `tab`, `pageup`, `pagedown`, `home`, `end`, `insert`, and `f1`, `f2`, … .
Character events use `char:x`, for example `char:a` or `char:A`.
Modifier flags are not passed separately to callbacks.

F5 is reserved for host zoom. Ctrl-C is reserved for host exit. Esc reaches
the application; implement quitting explicitly if desired.

Terminals differ in repeat and release reporting. New-press detection and
`is_down` use a 200 ms last-event timeout; they are approximations, and a
long hold without repeat events may expire. Release callbacks require terminal
support. Do not depend on `keyup` alone to finalize essential saved state.

### Mouse

| Callback | Arguments |
| --- | --- |
| `app.mousepressed(button, x, y)` | Button name, terminal column, terminal row. |
| `app.mousereleased(button, x, y)` | Button name, terminal column, terminal row. |
| `app.mousedragged(button, x, y)` | Button name, terminal column, terminal row. |
| `app.mousemoved(x, y)` | Terminal column and row. |
| `app.mousewheel(dx, dy, x, y)` | Wheel deltas and terminal position. |

Buttons are `"left"`, `"right"`, and `"middle"`. Wheel deltas are:
up `(0, 1)`, down `(0, -1)`, left `(-1, 0)`, right `(1, 0)`.

**Coordinate distinction:** the current host forwards 1-based terminal-global
mouse positions without subtracting the app window's origin or borders.
Graphics positions are relative to the content area. There is currently no
module function exposing that origin. Avoid assuming mouse and graphics
coordinates match in floating-window mode; even zoomed mode includes borders.
Mouse delivery also depends on terminal mouse reporting.

## Modules

| Module | Purpose |
| --- | --- |
| [`kkc`](#kkc) | Application identity, arguments, time, and exit. |
| [`kkc-graphics`](#kkc-graphics) | Character-cell drawing and colors. |
| [`kkc-key`](#kkc-key) | Key constants and held-key polling. |
| [`kkc-mouse`](#kkc-mouse) | Mouse constants. |
| [`kkc-rand`](#kkc-rand) | Pseudo-random numbers. |
| [`kkc-fs`](#kkc-fs) | File and directory operations. |
| [`kkc-shell`](#kkc-shell) | Synchronous program execution. |
| [`kkc-dialog`](#kkc-dialog) | Native modal dialogs. |
| [`kkc-audio`](#kkc-audio) | Terminal bell and audio playback. |

### `kkc`

```lua
local kkc = require("kkc")
```

| Member | Result / behavior |
| --- | --- |
| `quit()` | Requests exit from the host loop; does not immediately interrupt the callback. |
| `time()` → number | Seconds elapsed since the app started. |
| `args()` → table | New 1-based table of launcher argument strings. |
| `get_cwd()` → string | Launch working directory. |
| `cwd` | Launch working directory string, also available as a field. |
| `id`, `name`, `version` | Application metadata strings. |

### `kkc-graphics`

```lua
local gfx = require("kkc-graphics")
```

| Function | Behavior |
| --- | --- |
| `size()` → width, height | Current drawing-buffer dimensions. |
| `clear(ch?)` | Fills the entire buffer with the first character of `ch`, default space, using current colors. |
| `put(x, y, ch)` | Draws the first character of `ch`; empty string becomes a space. |
| `text(x, y, text)` | Draws a string starting at column `x`, row `y`. |
| `print(row, col, text)` | Row-first alias for `text(col, row, text)`. |
| `box(x, y, w, h, ch?)` | Fills a rectangle, defaulting to spaces. This is a filled area, not an outline. |
| `color(fg, bg)` | Sets both current colors as `0xRRGGBB` integers. |
| `set_fg(fg)` | Changes foreground only. |
| `set_bg(bg)` | Changes background only. |
| `reset()` | Restores white foreground on black background. |

Drawing is clipped to the content area. Colors apply to later drawing calls;
they do not recolor existing cells. The buffer stores one Unicode scalar per
cell, without grapheme or display-width layout. Prefer single-column glyphs.
`text` does not lay out multiline strings; split lines and draw each row.

```lua
gfx.reset()
gfx.clear()
gfx.color(0xFFFFFF, 0x245080)
gfx.box(2, 2, 20, 3)
gfx.text(3, 3, "A filled panel")
gfx.reset()
```

### `kkc-key`

| Member | Value / behavior |
| --- | --- |
| `LEFT`, `RIGHT`, `UP`, `DOWN` | Corresponding lowercase key strings. |
| `SPACE`, `ENTER`, `ESC` | `"space"`, `"enter"`, `"esc"`. |
| `HAS_RELEASE_EVENTS` | Boolean from the terminal's keyboard enhancement support probe. |
| `is_down(name)` → boolean | Whether the key has a recent press/repeat timestamp. |

```lua
local key = require("kkc-key")
-- Inside app.update(dt):
if key.is_down(key.LEFT) then
    -- Move left using dt.
end
```

The [keyboard callback notes](#keyboard-and-focus) explain repeat and timeout
limitations. The support flag does not remove those limitations.

### `kkc-mouse`

Constants only; events arrive through callbacks.

| Constants | String values |
| --- | --- |
| `LEFT`, `RIGHT`, `MIDDLE` | `"left"`, `"right"`, `"middle"` |
| `UP`, `DOWN`, `DRAG`, `MOVE` | `"up"`, `"down"`, `"drag"`, `"move"` |
| `SCROLL_UP`, `SCROLL_DOWN` | `"scroll_up"`, `"scroll_down"` |
| `SCROLL_LEFT`, `SCROLL_RIGHT` | `"scroll_left"`, `"scroll_right"` |

### `kkc-rand`

| Function | Behavior |
| --- | --- |
| `seed(number)` | Sets the generator's integer seed. |
| `int(min, max)` → integer | Inclusive integer range; reversed bounds are normalized. |
| `float()` → number | Value in `[0, 1)`. |

```lua
local rand = require("kkc-rand")
rand.seed(42)
local die = rand.int(1, 6)
```

The generator is seeded at startup. Use an explicit seed for reproducible
sequences in your own application logic.

### `kkc-fs`

Relative paths resolve from the application directory. Absolute paths are
used as supplied. These helpers do not restrict access to that directory.

| Function | Result / behavior |
| --- | --- |
| `exists(path)` → boolean | Whether a path exists. |
| `is_dir(path)` → boolean | Whether a path is a directory. |
| `read_text(path)` → string | Reads a UTF-8 text file; raises an error on failure. |
| `write_text(path, content)` | Writes/replaces text, creating parent directories. |
| `list_dir(path?)` → table | 1-based table of entry names, not full paths; defaults to the app directory. Ordering is unspecified. |
| `mkdir_all(path)` | Creates the directory and missing parents. |
| `join(a, b)` → string | Joins paths with platform path rules; an absolute `b` replaces `a`. |

```lua
local fs = require("kkc-fs")
local entries = fs.list_dir()
table.sort(entries)
for _, name in ipairs(entries) do
    -- name is relative to the listed directory.
end
```

### `kkc-shell`

| Function | Result / behavior |
| --- | --- |
| `run(program, args?, cwd?)` → table | Executes a program synchronously with optional string-array arguments. |
| `cwd()` → string | Default launch working directory. |

The result contains `ok` (boolean success), `code` (integer exit code or `-1`),
`stdout` (string), and `stderr` (string). Failure to start the program raises
an error; a started process returning a nonzero exit code produces a result
with `ok = false`.

The default working directory is the launch directory. Standard input is
closed and `GIT_TERMINAL_PROMPT=0` is set. This is process execution, not shell
parsing. There is no asynchronous execution or timeout argument in this API.

### `kkc-dialog`

Import with `local dialog = require("kkc-dialog")`. Interactive functions block
until the dialog closes; call them from an action callback, not every `draw`.

| Function | Result / behavior |
| --- | --- |
| `message(text)` | Displays a message; Enter or Esc dismisses it. |
| `input(prompt, default?)` → string | Default is `""`. Esc or accepting an empty value returns the default. |
| `confirm(prompt, default_yes?)` → boolean | Default is `true`. Y/N choose explicitly; Enter and Esc return the default. |
| `select(prompt, options, default_idx?)` → integer or nil | Options are strings; returns a 1-based index or `nil` on cancellation/empty options. Default index is 1. |
| `select_with_checks(prompt, options, default_idx?, checkboxes?, theme_name?)` → table | Returns optional `index` and a `checks` array of booleans. |
| `confirm_box(spec)` → table | Prepares a confirmation-dialog specification; does not display it. |
| `input_box(spec)` → table | Prepares an input-dialog specification; does not display it. |

For `select_with_checks`, each checkbox is a label string (initially unchecked)
or `{ label = "Recursive", checked = true }`. On cancellation, `index` is
absent; `checks` still contains checkbox states. `theme_name` can be
`"command_palette"` or `"remote_connections"`.

The two `*_box` helpers support the host's macro specification flow. They
normalize `buttons.items` callback IDs using an optional `spec.callback(item)`
returning a string or table with `id`/`callback`, replace `spec.callback` with
an empty table, and return the modified specification. Use the interactive
functions above to show a dialog from an application.

### `kkc-audio`

| Function | Result / behavior |
| --- | --- |
| `beep()` | Emits the terminal bell. |
| `play_audio(path)` → table | Starts playback; returns metadata `{ name, format, songs }`. |
| `stop_audio()` | Stops the current host audio playback. |
| `is_audio_playing()` → boolean | Whether host audio playback is active. |

Playback uses the host audio engine and available decoders/plugins. Format
support depends on the installed KKC build and plugins. The bell may be
silent according to terminal settings.

`play_audio` passes the path directly to the host: it does not resolve it
relative to the app directory like `kkc-fs`. Pass an absolute path, for example
one resolved from a launcher argument using `fs.join(kkc.get_cwd(), arg)`.
Audio state is shared with the host; the Kapsule loop does not automatically
stop it when the app exits.
