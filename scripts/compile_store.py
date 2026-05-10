#!/usr/bin/env python3
"""Compile plugin and application descriptors into a single store index for kkc.

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

ALLOWED_PLUGIN_TYPES = {"viewer", "archive", "action", "remote-rust", "other"}
ALLOWED_APPLICATION_TYPES = {"external_viewer", "external_editor"}
ALLOWED_APPLICATION_CATEGORIES = {
    "archive",
    "conversion",
    "development",
    "editor",
    "media",
    "network",
    "system",
    "utility",
    "viewer",
    "other",
}
ALLOWED_INSTALL_METHODS = {
    "apt",
    "brew",
    "cargo",
    "dnf",
    "manual",
    "pacman",
    "script",
    "scoop",
    "winget",
}


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


def as_required_str_list(value, field: str) -> list[str]:
    if isinstance(value, str):
        value = [value]
    result = as_str_list(value, field)
    if not result:
        fail(f"{field} must contain at least one string")
    if any(not item.strip() for item in result):
        fail(f"{field} must not contain empty strings")
    return result


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

    if ptype not in ALLOWED_PLUGIN_TYPES:
        fail(f"plugin.type must be one of {sorted(ALLOWED_PLUGIN_TYPES)}")

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


def validate_install_method(method: dict, index: int) -> dict:
    if not isinstance(method, dict):
        fail("install entries must be tables")

    prefix = f"install[{index}]"
    install_method = method.get("method")
    if not isinstance(install_method, str) or not install_method.strip():
        fail(f"{prefix}.method must be a non-empty string")
    if install_method not in ALLOWED_INSTALL_METHODS:
        fail(f"{prefix}.method must be one of {sorted(ALLOWED_INSTALL_METHODS)}")

    os_values = as_required_str_list(method.get("os"), f"{prefix}.os")
    normalized: dict[str, object] = {
        "os": os_values,
        "method": install_method,
    }

    string_fields = ("package", "crate", "command", "url", "bin")
    for field in string_fields:
        value = method.get(field)
        if value is not None:
            if not isinstance(value, str) or not value.strip():
                fail(f"{prefix}.{field} must be a non-empty string")
            normalized[field] = value

    args = method.get("args")
    if args is not None:
        normalized["args"] = as_str_list(args, f"{prefix}.args")

    if install_method == "cargo" and "crate" not in normalized and "package" not in normalized:
        fail(f"{prefix} cargo method must define crate or package")
    if install_method in {"apt", "brew", "dnf", "pacman", "scoop", "winget"} and "package" not in normalized:
        fail(f"{prefix} {install_method} method must define package")
    if install_method == "script" and "command" not in normalized:
        fail(f"{prefix} script method must define command")
    if install_method == "manual" and "url" not in normalized and "command" not in normalized:
        fail(f"{prefix} manual method must define url or command")

    return normalized


def validate_application(desc: dict, descriptor_path: Path, repo_root: Path) -> dict:
    application = desc.get("application")
    if not isinstance(application, dict):
        fail("missing [application] table")

    aid = application.get("id")
    name = application.get("name")
    version = application.get("version")
    description = application.get("description")
    category = application.get("category")

    for key, val in {
        "application.id": aid,
        "application.name": name,
        "application.description": description,
        "application.category": category,
    }.items():
        if not isinstance(val, str) or not val.strip():
            fail(f"{key} must be a non-empty string")

    if version is not None and (not isinstance(version, str) or not version.strip()):
        fail("application.version must be a non-empty string when present")

    if category not in ALLOWED_APPLICATION_CATEGORIES:
        fail(f"application.category must be one of {sorted(ALLOWED_APPLICATION_CATEGORIES)}")

    app_type = application.get("type")
    if app_type is not None:
        if not isinstance(app_type, str) or not app_type.strip():
            fail("application.type must be a non-empty string when present")
        if app_type not in ALLOWED_APPLICATION_TYPES:
            fail(f"application.type must be one of {sorted(ALLOWED_APPLICATION_TYPES)}")

    wait_for_key_after_exit = application.get("wait_for_key_after_exit", False)
    if not isinstance(wait_for_key_after_exit, bool):
        fail("application.wait_for_key_after_exit must be a boolean when present")

    mime_types = as_str_list(application.get("mime_types"), "application.mime_types")
    install_entries = desc.get("install")
    if not isinstance(install_entries, list) or not install_entries:
        fail("applications must define at least one [[install]] table")
    install = [validate_install_method(method, i) for i, method in enumerate(install_entries)]

    extra = desc.get("extra")
    if extra is not None and not isinstance(extra, dict):
        fail("[extra] must be a table when present")

    rel_descriptor = descriptor_path.relative_to(repo_root).as_posix()

    return {
        "id": aid,
        "name": name,
        "version": version,
        "description": description,
        "category": category,
        "type": app_type,
        "wait_for_key_after_exit": wait_for_key_after_exit,
        "mime_types": mime_types,
        "install": install,
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


def build_index(repo_root: Path, plugins_dir: Path, applications_dir: Path) -> dict:
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

    application_descriptors = sorted(applications_dir.glob("*/apps.toml")) if applications_dir.exists() else []
    applications: list[dict] = []
    seen_application_ids: set[str] = set()

    for descriptor in application_descriptors:
        raw = load_toml(descriptor)
        application = validate_application(raw, descriptor, repo_root)
        aid = application["id"]
        if aid in seen_application_ids:
            fail(f"duplicate application id: {aid}")
        seen_application_ids.add(aid)
        applications.append(application)

    applications.sort(key=lambda a: a["id"])

    latest_tag = get_latest_tag(repo_root)

    return {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source_repo": "https://github.com/redbug26/kkc-store",
        "plugins_count": len(plugins),
        "plugins": plugins,
        "applications_count": len(applications),
        "applications": applications,
        "tag": latest_tag,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Compile kkc plugin store index")
    parser.add_argument("--root", default=".", help="Store repository root")
    parser.add_argument("--plugins-dir", default="plugins", help="Descriptors directory")
    parser.add_argument("--applications-dir", default="applications", help="Application descriptors directory")
    parser.add_argument("--out", default="dist/store-index.json", help="Output JSON path")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    plugins_dir = (root / args.plugins_dir).resolve()
    applications_dir = (root / args.applications_dir).resolve()
    out_path = (root / args.out).resolve()

    if not plugins_dir.exists():
        print(f"ERROR: plugins directory not found: {plugins_dir}", file=sys.stderr)
        return 2

    try:
        index = build_index(root, plugins_dir, applications_dir)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(index, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")

    print(f"OK: wrote {out_path}")
    print(f"OK: plugins indexed: {index['plugins_count']}")
    print(f"OK: applications indexed: {index['applications_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
