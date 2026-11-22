# kkc-store

Community plugin and application store for **kkc**.

- Local repository: `/Users/miguelvanhove/Dropbox/Sources/kkc-store`
- GitHub repository: `https://github.com/redbug26/kkc-store`

This repository may not contain every plugin binary or application package directly. Instead, it stores **plugin descriptors** and **application descriptors**, then generates a compiled **store index** (`dist/store-index.json`) that kkc can read to list and install plugins or applications.

## Contributions

Contributions are welcome. New plugins and applications can be proposed through pull requests; see [ADDING_TO_STORE.md](ADDING_TO_STORE.md) for the descriptor format and contribution workflow.

Applications listed in this store must be usable from a terminal/TUI context. They should open or run directly in the terminal so kkc TUI can launch them as external viewers, editors, or tools.

## Develop a Lua application

Read the [Lua application development guide](docs/lua-applications.md) to build
your first app, configure `[runtime]`, run it in KKC, and publish it in this
store. The [Lua API reference](docs/lua-api.md) documents callbacks and all
runtime modules with signatures and examples.

## Repository layout

```text
kkc-store/
  README.MD
  scripts/
    compile_store.py
  plugins/
    <plugin-id>/
      plugin.toml
  applications/
    <application-id>/
      apps.toml
  assets/
    plugins/
      <plugin-folder>/
        plugin.lua
  dist/
    store-index.json
```

## Descriptor formats

Each plugin is defined by a `plugin.toml` file. Each application is defined by an `apps.toml` file.

Main sections:

- `[plugin]`: metadata inspired by `kkc.register_viewer_plugin` and `kkc.register_archive_plugin`
- `[location]`: where the plugin can be fetched (local path or GitHub source)

Common fields in `[plugin]`:

- `id` (unique)
- `name`
- `version`
- `type` (`viewer`, `archive`, `action`, `other`)
- `description`
- `mime_types` (list)
- `modes` (list, optional, mostly for viewers)

Fields in `[location]`:

- `kind = "local"`:
  - `path` (path relative to this repository)
- `kind = "github"`:
  - `repo` (`owner/repo`)
  - `path` (path in repository) **or** `asset_url` (release/download URL)
  - `ref` (branch/tag/commit, optional, defaults to `main`)

Application descriptors use:

- `[application]`: metadata for an application kkc TUI can install directly
- `[[install]]`: one or more OS-specific install methods (`cargo`, `brew`, `apt`, etc.)
- `[extra]`: optional metadata

Common fields in `[application]`:

- `id` (unique)
- `name`
- `version`
- `description`
- `category` (`archive`, `conversion`, `development`, `editor`, `media`, `network`, `system`, `utility`, `viewer`, `other`)
- `type` (`external_viewer` or `external_editor`, optional)
- `wait_for_key_after_exit` (boolean, optional, asks kkc to pause after applications that exit immediately)
- `mime_types` (list, optional)

See [ADDING_TO_STORE.md](ADDING_TO_STORE.md) for the full plugin and application TOML format.

## Build the store index

From the repository root:

```bash
python3 scripts/compile_store.py
```

Output:

- `dist/store-index.json`

## Bump version tag

To increment the version and create a new tag:

```bash
./release.sh              # Increment patch: 0.0.0 → 0.0.1
./release.sh minor        # Increment minor: 0.0.1 → 0.1.0
./release.sh major        # Increment major: 0.1.0 → 1.0.0
```

The script:
- Syncs `plugin.version` for every `location.kind = "github"` plugin using upstream source/release metadata
- Rebuilds `dist/store-index.json`
- Reads the latest tag (or defaults to `0.0.0` if none exist)
- Increments the version according to the specified type (patch, minor, major)
- Creates an annotated git tag
- Pushes the tag to GitHub

A GitHub Actions workflow automatically triggers when a new tag is pushed, recompiling `dist/store-index.json` and committing the updated index to `main`.

## Suggested workflow

1. For a plugin, add `plugins/<plugin-id>/plugin.toml`
2. For an application, add `applications/<application-id>/apps.toml`
3. Run `python3 scripts/compile_store.py`
4. Commit and push to `main`
5. kkc downloads/reads `dist/store-index.json` to display the store

## Examples

- `plugins/example-local/plugin.toml`
- `plugins/example-remote/plugin.toml`
- `applications/bat/apps.toml`
- `applications/micro/apps.toml`
