# kkc-plugins

Community plugin store for **kkc**.

- Local repository: `/Users/miguelvanhove/Dropbox/Sources/kkc-plugins`
- GitHub repository: `https://github.com/redbug26/kkc-plugins`

This repository may not contain every plugin binary directly. Instead, it stores **plugin descriptors** and generates a compiled **store index** (`dist/store-index.json`) that kkc can read to list and install plugins.

## Repository layout

```text
kkc-plugins/
  README.MD
  scripts/
    compile_store.py
  plugins/
    <plugin-id>/
      plugin.toml
  assets/
    plugins/
      <plugin-folder>/
        plugin.lua
  dist/
    store-index.json
```

## Descriptor format

Each plugin is defined by a `plugin.toml` file.

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

## Build the store index

From the repository root:

```bash
python3 scripts/compile_store.py
```

Output:

- `dist/store-index.json`

## Suggested workflow

1. Add a directory `plugins/<plugin-id>/`
2. Add `plugins/<plugin-id>/plugin.toml`
3. Run `python3 scripts/compile_store.py`
4. Commit and push to `main`
5. kkc downloads/reads `dist/store-index.json` to display the plugin store

## Examples

- `plugins/example-local/plugin.toml`
- `plugins/example-remote/plugin.toml`
# kkc-plugins
