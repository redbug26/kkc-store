#!/usr/bin/env python3
"""Compile plugin descriptors into a single store index for kkc.

Usage:
  python3 scripts/compile_store.py
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:
    print("ERROR: Python 3.11+ is required (tomllib missing)", file=sys.stderr)
    sys.exit(2)

ALLOWED_TYPES = {"viewer", "archive", "action", "other"}


def fail(msg: str) -> None:
    raise ValueError(msg)


def load_toml(path: Path) -> dict:
    with path.open("rb") as f:
        return tomllib.load(f)


def as_str_list(value, field: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list) or not all(isinstance(x, str) for x in value):
        fail(f"{field} must be a list of strings")
    return value


def validate_plugin(desc: dict, descriptor_path: Path, repo_root: Path) -> dict:
    plugin = desc.get("plugin")
    if not isinstance(plugin, dict):
        fail("missing [plugin] table")

    location = desc.get("location")
    if not isinstance(location, dict):
        fail("missing [location] table")

    pid = plugin.get("id")
    name = plugin.get("name")
    version = plugin.get("version")
    ptype = plugin.get("type")
    description = plugin.get("description")

    for key, val in {
        "plugin.id": pid,
        "plugin.name": name,
        "plugin.version": version,
        "plugin.type": ptype,
        "plugin.description": description,
    }.items():
        if not isinstance(val, str) or not val.strip():
            fail(f"{key} must be a non-empty string")

    if ptype not in ALLOWED_TYPES:
        fail(f"plugin.type must be one of {sorted(ALLOWED_TYPES)}")

    mime_types = as_str_list(plugin.get("mime_types"), "plugin.mime_types")
    modes = as_str_list(plugin.get("modes"), "plugin.modes")

    kind = location.get("kind")
    if kind not in {"local", "github"}:
        fail("location.kind must be 'local' or 'github'")

    normalized_location: dict[str, str] = {"kind": kind}
    if kind == "local":
        lpath = location.get("path")
        if not isinstance(lpath, str) or not lpath.strip():
            fail("location.path must be a non-empty string for local plugins")
        local_path = Path(lpath)
        if local_path.is_absolute():
            fail("location.path must be relative to the plugin.toml directory for local plugins")
        resolved_local = (descriptor_path.parent / local_path).resolve()
        try:
            repo_relative_local = resolved_local.relative_to(repo_root)
        except ValueError:
            fail("local location.path must resolve inside the repository")
        normalized_location["path"] = f"/{repo_relative_local.as_posix()}"
    else:
        repo = location.get("repo")
        ref = location.get("ref", "main")
        path = location.get("path")
        asset_url = location.get("asset_url")

        if not isinstance(repo, str) or "/" not in repo:
            fail("location.repo must be in owner/repo format for github plugins")
        if not isinstance(ref, str) or not ref.strip():
            fail("location.ref must be a non-empty string")
        if path is None and asset_url is None:
            fail("github location must define location.path or location.asset_url")
        if path is not None and not isinstance(path, str):
            fail("location.path must be a string")
        if asset_url is not None and not isinstance(asset_url, str):
            fail("location.asset_url must be a string")

        normalized_location["repo"] = repo
        normalized_location["ref"] = ref
        if path:
            normalized_location["path"] = path
        if asset_url:
            normalized_location["asset_url"] = asset_url

    extra = desc.get("extra")
    if extra is not None and not isinstance(extra, dict):
        fail("[extra] must be a table when present")

    rel_descriptor = descriptor_path.relative_to(repo_root).as_posix()

    return {
        "id": pid,
        "name": name,
        "version": version,
        "type": ptype,
        "description": description,
        "mime_types": mime_types,
        "modes": modes,
        "location": normalized_location,
        "descriptor": rel_descriptor,
        "extra": extra or {},
    }


def get_latest_tag(repo_root: Path) -> str | None:
    """Get the latest git tag, or None if no tags exist."""
    try:
        result = subprocess.run(
            ["git", "describe", "--tags", "--abbrev=0"],
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return None


def build_index(repo_root: Path, plugins_dir: Path) -> dict:
    descriptors = sorted(plugins_dir.glob("*/plugin.toml"))
    plugins: list[dict] = []
    seen_ids: set[str] = set()

    for descriptor in descriptors:
        raw = load_toml(descriptor)
        plugin = validate_plugin(raw, descriptor, repo_root)
        pid = plugin["id"]
        if pid in seen_ids:
            fail(f"duplicate plugin id: {pid}")
        seen_ids.add(pid)
        plugins.append(plugin)

    plugins.sort(key=lambda p: p["id"])

    latest_tag = get_latest_tag(repo_root)

    return {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source_repo": "https://github.com/redbug26/kkc-plugins",
        "plugins_count": len(plugins),
        "plugins": plugins,
        "tag": latest_tag,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Compile kkc plugin store index")
    parser.add_argument("--root", default=".", help="Store repository root")
    parser.add_argument("--plugins-dir", default="plugins", help="Descriptors directory")
    parser.add_argument("--out", default="dist/store-index.json", help="Output JSON path")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    plugins_dir = (root / args.plugins_dir).resolve()
    out_path = (root / args.out).resolve()

    if not plugins_dir.exists():
        print(f"ERROR: plugins directory not found: {plugins_dir}", file=sys.stderr)
        return 2

    try:
        index = build_index(root, plugins_dir)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(index, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")

    print(f"OK: wrote {out_path}")
    print(f"OK: plugins indexed: {index['plugins_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
