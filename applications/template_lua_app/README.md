# KKC Lua Application Starter

This template is a starting point for shipping a Lua terminal app for KKC.

## Run locally in KKC

1. Copy this folder under your KKC data applications directory as `my_lua_app`.
2. Create `app.toml` with an `[app]` table containing `id`, `name`, `version`, and `description` from `[application]`, plus `main` and `fps` from `[runtime]` in `apps.toml` (required by the current KKC runtime).
3. Add an association command like: `kkc-lua-app:my_lua_app %f`
4. Open a file that matches the association to launch the app.

## Files

- `apps.toml`: store metadata, installation instructions, and Lua runtime parameters.
- `src/app.lua`: app entrypoint.
- `.luacheckrc`: lint configuration.
- `.github/workflows/lua-lint.yml`: CI workflow for Lua linting.

## Runtime modules

- `require("kkc")`
- `require("kkc-graphics")`
- `require("kkc-key")`
- `require("kkc-mouse")`
- `require("kkc-rand")`
- `require("kkc-fs")`
- `require("kkc-audio")`
