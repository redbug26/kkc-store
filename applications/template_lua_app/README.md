# KKC Kapsule Starter

This template is a starting point for shipping a Kapsule: a Lua terminal application for KKC.

Follow the [development guide](../../docs/lua-applications.md) for a complete
first application, configuration, testing, and publishing. See the
[API reference](../../docs/lua-api.md) for callbacks and module functions.

## Run locally in KKC

1. Copy this folder under your KKC data applications directory as `my_lua_app`.
2. Add an association command like: `kkc-lua-app:my_lua_app %f`
3. Open a file that matches the association to launch the app.

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
- `require("kkc-shell")`
- `require("kkc-dialog")`
- `require("kkc-audio")`
