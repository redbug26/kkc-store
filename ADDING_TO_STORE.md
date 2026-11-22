# Adding a Plugin or Application

This repository contains the descriptors used by kkc TUI to build `dist/store-index.json`.

For Lua application development, start with the [development guide](docs/lua-applications.md)
and [API reference](docs/lua-api.md). The guide explains the store descriptor,
the shared runtime descriptor, and how to test an app inside KKC.

## Contribution Workflow

To propose a new plugin or application, first fork this repository on GitHub. Add your descriptor in your fork, run the index compiler locally, then open a pull request back to this repository.

For applications, the expected workflow is:

1. Fork the repository.
2. Create `applications/<application-id>/apps.toml` in your fork.
3. Run `python3 scripts/compile_store.py`.
4. Commit both the descriptor and the updated `dist/store-index.json`.
5. Open a pull request with a short explanation of what the application does and which install methods were tested or verified.

## Application Categories

Applications must use one of the following categories:

- `archive`: archive and compression tools.
- `conversion`: file or format conversion tools.
- `development`: development tools.
- `editor`: external editors.
- `media`: audio, image, video, or multimedia document tools.
- `network`: networking or transfer tools.
- `system`: system tools.
- `utility`: general-purpose utilities.
- `viewer`: external viewers.
- `other`: anything that does not fit the categories above.

## Plugin

Create a `plugins/<plugin-id>/` directory containing `plugin.toml`.

```toml
[plugin]
id = "json-viewer"
name = "JSON Viewer"
version = "1.2.0"
type = "viewer"
description = "External JSON viewer"
mime_types = ["application/json", "text/json"]
modes = ["text"]

[location]
kind = "local"
path = "assets"

[extra]
author = "community"
license = "MIT"
```

Required fields in `[plugin]`:

- `id`: unique store identifier.
- `name`: display name shown by kkc TUI.
- `version`: plugin version.
- `type`: `viewer`, `archive`, `action`, or `other`.
- `description`: short description.

Optional fields in `[plugin]`:

- `mime_types`: list of MIME types handled by the plugin, empty by default.
- `modes`: list of modes, mostly useful for viewers.

The `[location]` section describes where the plugin can be fetched from:

```toml
[location]
kind = "local"
path = "assets"
```

`path` is relative to the directory containing `plugin.toml`.

```toml
[location]
kind = "github"
repo = "owner/repo"
path = "path/in/repo"
ref = "main"
```

For `kind = "github"`, use either `path` or `asset_url`. `ref` is optional and defaults to `main`.

## Application

Create an `applications/<application-id>/` directory containing `apps.toml`.

```toml
[application]
id = "bat"
name = "bat"
version = "0.25.0"
description = "Syntax-highlighting text viewer usable as an external viewer."
category = "viewer"
type = "external_viewer"
wait_for_key_after_exit = false
mime_types = ["text/plain", "text/markdown", "application/json"]

[[install]]
os = ["macos", "linux"]
method = "cargo"
crate = "bat"
bin = "bat"

[[install]]
os = "macos"
method = "brew"
package = "bat"
bin = "bat"

[[install]]
os = ["debian", "ubuntu"]
method = "apt"
package = "bat"
bin = "batcat"

[extra]
homepage = "https://github.com/sharkdp/bat"
license = "Apache-2.0 OR MIT"
```

Required fields in `[application]`:

- `id`: unique application identifier.
- `name`: display name shown by kkc TUI.
- `version`: application version.
- `description`: short description.
- `category`: one of the categories documented above.

Optional fields in `[application]`:

- `mime_types`: list of associated MIME types, empty by default.
- `type`: `external_viewer` or `external_editor`. Omit this field if the application is not tied to a specific role.
- `wait_for_key_after_exit`: boolean, defaults to `false`. Set to `true` for applications that render output and then return to the system immediately, so kkc can show a “Press a key to continue” prompt after execution.

Optional fields in the `[runtime]` section for Lua applications:

- `main`: Lua entrypoint path relative to the application directory.
- `fps`, `width`, `height`: positive integers for Lua runtime frame rate and terminal dimensions. These settings are preserved in a nested `runtime` object in the store index when present.

Lua applications keep their metadata in `[application]` and execution settings in `[runtime]` within the same `apps.toml`. KKC reads this descriptor directly. Distribute it alongside the Lua files and required assets.

Each application must define at least one `[[install]]` table.

Required fields in `[[install]]`:

- `os`: string or list of strings (`macos`, `linux`, `debian`, `ubuntu`, `windows`, etc.).
- `method`: `cargo`, `brew`, `apt`, `dnf`, `pacman`, `winget`, `scoop`, `script`, or `manual`.

Optional fields in `[[install]]`:

- `package`: package name for `brew`, `apt`, `dnf`, `pacman`, `winget`, or `scoop`.
- `crate`: crate name for `cargo`.
- `command`: command for `script` or a manual instruction.
- `url`: URL for `manual`.
- `bin`: expected binary after installation.
- `args`: additional arguments as a list.

Validation rules:

- `cargo` must define `crate` or `package`.
- `brew`, `apt`, `dnf`, `pacman`, `winget`, and `scoop` must define `package`.
- `script` must define `command`.
- `manual` must define `url` or `command`.

## Compile the Index

From the repository root:

```bash
python3 scripts/compile_store.py
```

The script validates every `plugins/*/plugin.toml` and `applications/*/apps.toml` file, then writes `dist/store-index.json`.
