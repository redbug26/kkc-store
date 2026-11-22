# Developing Kapsules for KKC

The standalone [Kapsule Rust runtime](https://github.com/redbug26/kapsule-rust) is the reference
implementation for Kapsule execution. KKC Rust, KKC iPad and Kommando iPad must
follow its changes. The development guide and API documentation remain in
the [development guide](https://github.com/redbug26/kkc-store/blob/main/docs/lua-applications.md) and [API reference](https://github.com/redbug26/kkc-store/blob/main/docs/lua-api.md) in **kkc-store**.

A **Kapsule** is a Lua application running in the standalone Kapsule reader or a compatible KKC/Kommando host. Build terminal tools
and games with Lua 5.4. The host supplies the window, event loop,
keyboard and mouse events, a character-cell drawing buffer, and access to files,
processes, dialogs, and audio. Your application returns a table of callbacks.

**Start here:** [First application](#first-application) ·
[Configuration](#configuration) · [Lifecycle](#lifecycle) ·
[Recipes](#recipes) · [Testing](#testing-and-troubleshooting) ·
[Publishing](#publishing)

**Reference:** [Callbacks and modules](lua-api.md)

## First application

### 1. Create a directory

Create this layout in any directory, for example `hello_lua/`. To use KKC
discovery, place it under `applications/hello_lua/` in the KKC data directory:

```text
hello_lua/
  apps.toml
  src/
    app.lua
```

KKC discovers installed applications in `<KKC data directory>/applications`
and also searches `<KKC data directory>/plugins`. This is the platform data
directory selected by KKC's `ProjectDirs::from("be", "kyuran", "kkc")`,
not this repository's `applications/` directory. You can locate it by finding
an installed application's `apps.toml`, such as `snake` or `calculator`.

You can also start from the [starter template](../applications/template_lua_app/).
Use a new application ID to avoid colliding with bundled applications.

### 2. Describe your application

Save this as `apps.toml`. It is the source descriptor used by this store:

```toml
[application]
id = "hello_lua"
name = "Hello Lua"
version = "0.1.0"
description = "A moving marker in a KKC terminal window"
category = "utility"

[runtime]
main = "src/app.lua"
fps = 30
width = 60
height = 18

[[install]]
os = ["macos", "linux", "windows"]
method = "manual"
command = "Copy the complete app directory into the KKC data applications directory and launch it inside KKC."
```

KKC reads this same `apps.toml` directly: `[application]` provides metadata
and `[runtime]` provides execution settings. Keep this descriptor alongside
the Lua files when installing or distributing the app.

### 3. Write the application

Save this complete example as `src/app.lua`:

```lua
local kkc = require("kkc")
local gfx = require("kkc-graphics")
local key = require("kkc-key")

local app = {}
local width, height = 1, 1
local x = 1
local paused = false

function app.resize(w, h)
    width, height = w, h
    x = math.min(x, math.max(1, width))
end

function app.update(dt)
    if not paused then
        x = 1 + ((x - 1 + 8 * dt) % math.max(1, width))
    end
end

function app.keypressed(k)
    if k == key.ESC then
        kkc.quit()
    end
end

function app.keydown(k)
    if k == key.SPACE then
        paused = not paused
    end
end

function app.draw()
    gfx.reset()
    gfx.clear()
    gfx.color(0x80D8FF, 0x000000)
    gfx.text(2, 2, paused and "Paused" or "Hello from KKC")
    gfx.put(math.floor(x), math.max(1, math.floor(height / 2)), "@")
end

function app.shortcuts()
    return { "Space:Pause", "F5:Zoom", "Esc:Quit" }
end

return app
```

`update(dt)` moves the marker at eight cells per second. `draw()` paints the
current state. The example uses `keydown` for a toggle so repeated key events
do not continually change it. Terminals without distinct release events use
a timeout to approximate separate presses.

### 4. Launch it with the reference reader

A Kapsule can live in any directory. Install the standalone reader from
[kapsule-rust](https://github.com/redbug26/kapsule-rust) with
`cargo install --git https://github.com/redbug26/kapsule-rust --locked`, then run:

```sh
kapsule /path/to/hello_lua
kapsule /path/to/hello_lua/apps.toml -- argument1 argument2
kapsule --check /path/to/hello_lua
kapsule --headless 60 --dump-screen /path/to/hello_lua
```

Use the built `target/release/kapsule` path, or install it with
`cargo install --path . --locked`. No KKC installation or system Lua is needed.
The reference reader starts zoomed; `--windowed` uses the manifest window.
F5 toggles zoom, Ctrl-C exits, and Esc reaches your callback. `--cwd DIR`
sets `kkc.get_cwd()` and the default process directory; relative `kkc-fs`
paths still resolve from the Kapsule directory.

`--check` checks the descriptor and entry syntax without executing Lua.
Headless mode runs up to the requested number of frames at `1/fps`, without
input, using an 80×24 terminal (78×22 content when zoomed). Interactive dialogs
require a terminal. The screen dump contains only the Lua buffer.

### 5. Launch it in KKC

Open **Tools > Run Lua app** and choose **Hello Lua**. An opener or file
association can also use the internal command `kkc-lua-app:hello_lua`.
For a file-aware application, use `kkc-lua-app:hello_lua %f`; the expanded
arguments are available in `ctx.args` and `kkc.args()`.

This is an internal KKC command, not a shell executable. Running the Lua file
with a standalone interpreter does not provide the `kkc-*` modules.

Press **Space** to pause, **F5** to toggle window/full-screen mode, and **Esc**
to quit through the callback. **Ctrl-C** is handled by the host as a quit key.

## Configuration

Store metadata belongs in `[application]`. Application-specific execution
settings belong in `[runtime]` and are preserved under `runtime` in the
compiled JSON index.

| Runtime field | Type | Runtime default | Meaning |
| --- | --- | --- | --- |
| `main` | string | `"app.lua"` | Entry script, relative to the application directory. |
| `fps` | positive integer | `30` | Target frame rate; KKC clamps it to 10–120. |
| `width` | positive integer | `40` | Requested floating-window width, including borders. |
| `height` | positive integer | `20` | Requested floating-window height, including borders. |

Use `resize(w, h)` or `gfx.size()` for drawable dimensions. The host constrains
the window to fit the terminal. The shortcut footer, when present, occupies
the last drawable row. Leave that row free of important content.

`init(ctx)` currently receives the terminal dimensions before the floating
window is configured. The initial `resize` callback supplies the actual
content size before the first frame. Initialize layout there.

## Lifecycle

KKC loads the entry script, obtains the returned table, and calls optional
functions on it using ordinary function calls, without a `self` argument.
Define `function app.draw()`, rather than `function app:draw()`.

```text
load entry script → init(ctx) → resize(w, h)
                                   ↓
                   input / focus events between frames
                                   ↓
                 resize if needed → update(dt) → draw()
                                   ↓
                       shortcuts() → host renders
                                   ↓
                            next frame or exit
```

All callbacks run synchronously in the host loop. `dt` is elapsed time in
seconds, not a frame count. A slow operation delays drawing and input.
After a blocking dialog or process, the next `dt` can be large; games may
choose to clamp the simulation step, for example `dt = math.min(dt, 0.1)`.

The buffer and current colors persist between frames. Clear and redraw when
appropriate; `gfx.clear()` fills using the current colors, while `gfx.reset()`
resets colors without clearing. Resize discards the drawing buffer.

Exit with `kkc.quit()` and return from the current callback. There is no app
shutdown callback in the current runtime. Save state and stop app-owned audio
before requesting exit when needed.

## Recipes

### Organize local modules

`require("src.model")` loads `src/model.lua` under the application directory.
`require("widgets")` can load `widgets.lua` or `widgets/init.lua` there.
The entry script's location does not change the module root.

```lua
-- src/model.lua
return { title = "My tool", count = 0 }
```

```lua
local model = require("src.model")
model.count = model.count + 1
```

### Read the selected file

`kkc-fs` resolves relative paths against the application directory. Launcher
arguments may instead be relative to the launch working directory; resolve
them explicitly before reading:

```lua
local kkc = require("kkc")
local fs = require("kkc-fs")
local message = "No file selected"

local function load_selected_file(ctx)
    local path = ctx.args[1]
    if not path then return end
    local resolved = fs.join(kkc.get_cwd(), path)
    local ok, text = pcall(fs.read_text, resolved)
    message = ok and text or ("Cannot read file: " .. tostring(text))
end
-- Call load_selected_file(ctx) from app.init(ctx).
```

### Persist a setting

```lua
local fs = require("kkc-fs")
fs.write_text("state/score.txt", tostring(42))
local score = tonumber(fs.read_text("state/score.txt")) or 0
```

`write_text` creates parent directories. Handle read/write errors with `pcall`
when you want to display an error and keep the application open.

### Run a command

```lua
local shell = require("kkc-shell")
local ok, result = pcall(shell.run, "git", { "status", "--short" })
local message
if not ok then
    message = "Could not start Git: " .. tostring(result)
elseif result.ok then
    message = result.stdout
else
    message = result.stderr
end
```

Arguments are passed directly to a program; pipes and shell expansion are
not interpreted. This call waits for the process and captures its output.
Run it in response to an action rather than on every frame.

### Ask for input

```lua
local dialog = require("kkc-dialog")
local name = dialog.input("Application name", "Untitled")
local choice = dialog.select("Action", { "Open", "Save" }, 1)
if choice == 2 then
    dialog.message("Save selected for " .. name)
end
```

Dialogs block the application loop until dismissed. For `input`, Esc returns
the default string. `select` returns `nil` on cancellation.

## Testing and troubleshooting

Use the starter's [lint configuration](../applications/template_lua_app/.luacheckrc)
and [workflow](../applications/template_lua_app/.github/workflows/lua-lint.yml)
as a base. With Lua 5.4 and Luacheck installed, run from your app directory:

```sh
luac -p src/app.lua
luacheck src
```

Syntax checking and linting do not execute the host API. Exercise the app in
KKC: open it, change the terminal size, toggle F5, test repeated key presses,
lose/regain focus, and try missing files or a failed external command.

| Symptom | Check |
| --- | --- |
| App absent from launcher | Installed directory has `apps.toml` with `[application]` and a unique `id`; the `[runtime]` entry script exists. |
| App absent from store | `applications/<folder>/apps.toml` validates and the index has been rebuilt. |
| `module 'kkc-graphics' not found` | Launch inside KKC, not standalone Lua. |
| Empty window | Entry script returns `app`; `draw()` writes within `gfx.size()`; callbacks use dot syntax. |
| Incorrect layout after startup/F5 | Derive layout from `resize`, not only `init(ctx)`. |
| Mouse hit boxes offset | Mouse positions are terminal-global; drawing positions are content-local. See the reference. |
| Characters misalign | Prefer single-column glyphs; wide characters and combining marks are not laid out as full terminal graphemes. |
| UI freezes | Look for long callbacks, process execution, dialogs, or blocking file access. |

## Publishing

Keep `apps.toml`, your Lua files, and required assets together under
`applications/<folder>/` in this repository. Use the [contribution guide](../ADDING_TO_STORE.md)
for categories, install descriptors, and the pull request workflow.

The current Lua entries use manual installation. Copy the complete application
directory, including `apps.toml` and its Lua files, into the KKC data
applications directory. The store and runtime use the same descriptor.

From the store repository root, with Python 3.11 or newer:

```sh
python3 scripts/compile_store.py
```

Review the new entry in `dist/store-index.json`, including its `runtime`
object. Test the installed app in KKC before publishing it.

## Examples to explore

| Application | What to study |
| --- | --- |
| [Starter](../applications/template_lua_app/src/app.lua) | Modules, drawing, key and mouse callbacks. |
| [ASCII table](../applications/ascii/app.lua) | Text grids and selection. |
| [Calculator](../applications/calculator/app.lua) | Interactive input and display state. |
| [Calendar](../applications/calendar/app.lua) | Date-oriented terminal layout. |
| [Git Repo](../applications/git_repo/app.lua) | File-aware tooling and external commands. |
| [Snake](../applications/snake/app.lua) | Game state and timed movement. |
| [Tetris](../applications/tetris/app.lua) | Game loop and keyboard handling. |
| [Rockland](../applications/rockland/app.lua) | Local modules and a larger game. |
| [Pepper Buster](../applications/pepper_buster/README.md) | A source-verified arcade port with automatic integer zoom, a full-screen menu, and a separate deterministic engine. |

The API originated in KKC Rust. Its current authority is the standalone
[kapsule-rust runtime](https://github.com/redbug26/kapsule-rust), with
`src/runtime.rs`, `src/lua_dialog.rs` and `src/audio.rs`.

## Runtime evolution and consumer hosts

The source of truth is [kapsule-rust](https://github.com/redbug26/kapsule-rust), especially `src/runtime.rs`,
`src/lua_dialog.rs`, and `src/audio.rs`. For changes to manifests, callbacks,
module signatures or observable execution behavior, update this guide and
[lua-api.md](lua-api.md), add a compatibility check to the standalone runtime,
and synchronize `kkc/kkc-rust`, `ios/kkc`, and `ios/commando`.
Platform restrictions must keep the Lua API available and return explicit
errors for unavailable operations. Other KKC features retain their own references.

The standalone reader includes Symphonia audio decoding (WAV, MP3, FLAC, Ogg,
etc.), without KKC's tracker/native plugins. Unsupported formats raise a Lua
error. Dialog palette names are accepted with one shared beige style.

## Run a Kapsule in WebAssembly

The [reference runtime](https://github.com/redbug26/kapsule-rust) also builds for
`wasm32-unknown-emscripten`. In that repository, activate an Emscripten SDK,
install the Rust target, and run:

```sh
rustup target add --toolchain stable wasm32-unknown-emscripten
python3 tools/build_wasm.py
python3 tools/serve_web.py --port 8080
```

Open `http://localhost:8080`, select an example or use **Ouvrir un dossier** to
choose the directory containing `apps.toml`. All Lua modules and assets must
be included. The browser runs the shared Rust/Lua 5.4 engine, not a translation
of your Lua application. It reports real keyboard press/release events.

`kkc-fs` operates on a temporary in-memory filesystem, not the original folder.
Files changed by the application are lost when another Kapsule is opened or
the page is reloaded. Imported folders are limited to 64 MiB. No application
server or upload service is involved; `dist/web` is a static distribution.

Lua runs in a dedicated worker. A callback taking more than five seconds
(excluding browser dialogs) stops that worker, allowing another Kapsule to
start. Lua allocations are limited to 64 MiB; the WASM heap is capped at
512 MiB. Dialogs require HTTPS (or localhost) and the COOP/COEP headers
provided by the reference player’s Apache configuration and preview server.

Shell processes are unavailable: `kkc-shell.run` raises an explicit error.
Audio decoding depends on the browser; dialogs use its native modal windows.
See the [browser limitations](lua-api.md#webassembly-browser-host) before
porting an application that uses platform services.

### Public browser player and store loading

The browser player is hosted at [kapsule.kyuran.be](https://kapsule.kyuran.be/).
It lists every application with a `runtime` table from this repository's
compiled index. Select a Kapsule and click **Lancer**, or share a link such as
[Rockland](https://kapsule.kyuran.be/?kapsule=rockland), which preselects it.
**Actualiser le store** refreshes the catalogue.

Keep every required Lua module and asset in the directory containing the
application's `apps.toml`. The browser downloads that entire directory from
one pinned commit, using the index's `descriptor` field rather than assuming
the directory name equals the application ID. Binary assets are supported.
Downloads can be cancelled; the limit is 64 MiB and 4096 files per Kapsule.
Symlinks are not supported. The reader verifies the selected ID against the
manifest. External-process limitations still apply.

The website also bundles a complete store snapshot as JSON data packages
during its build; application files are never exposed as executable server
files. Each publication rebuilds WASM and refreshes that snapshot, then
removes its temporary compilation and publication directories. If GitHub
is unavailable or rate limited, the bundled catalogue and files are used.
Publish changes through the normal store index workflow to make them discoverable;
users may need to refresh the player catalogue. The player build/publication
commands are in the [reference repository](https://github.com/redbug26/kapsule-rust).
