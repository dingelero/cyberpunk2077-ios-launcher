#!/usr/bin/env python3
"""Hash original, read-only Steam resources without copying large archives."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

BUFFER_BYTES = 4 * 1024 * 1024
FORMAT = "CPResourceManifestV1"
MACHO_MAGICS = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}


def is_ep1(path: str) -> bool:
    parts = PurePosixPath(path).parts
    return "ep1" in parts or PurePosixPath(path).name in {"ep1.addcont_keystone", "tweakdb_ep1.bin"}


def in_scope(path: str, scope: str) -> bool:
    return scope == "all" or not is_ep1(path)


def valid_resource_path(path: str) -> bool:
    name = PurePosixPath(path)
    if name.is_absolute() or ".." in name.parts or not name.parts:
        return False
    return name.parts[0] in {"archive", "engine", "r6"} or path == "Cyberpunk2077.app/Contents/Info.plist" or path.startswith("Cyberpunk2077.app/Contents/Resources/")


def resource_files(root: Path, scope: str):
    candidates = []
    for directory in ("archive", "engine", "r6", "Cyberpunk2077.app/Contents/Resources"):
        location = root / directory
        if not location.is_dir():
            raise RuntimeError(f"Missing resource directory: {location}")
        candidates.extend(p for p in location.rglob("*") if p.is_file())
    candidates.append(root / "Cyberpunk2077.app/Contents/Info.plist")
    for source in sorted(candidates):
        if not source.is_file():
            raise RuntimeError(f"Missing resource: {source}")
        if not source.resolve().is_relative_to(root.resolve()):
            raise RuntimeError(f"Resource symlink escapes source root: {source}")
        relative = source.relative_to(root).as_posix()
        if not in_scope(relative, scope):
            continue
        with source.open("rb") as file:
            if file.read(4) in MACHO_MAGICS:
                raise RuntimeError(f"Original macOS Mach-O must not be transferred as a resource: {relative}")
        yield source, relative


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        while chunk := file.read(BUFFER_BYTES):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def create_manifest(root: Path, scope: str, output: Path) -> dict:
    root = root.resolve()
    files = list(resource_files(root, scope))
    entries = []
    for index, (source, relative) in enumerate(files, 1):
        before = source.stat()
        print(f"hash [{index}/{len(files)}] {relative} ({before.st_size:,} bytes)", flush=True)
        digest = hash_file(source)
        after = source.stat()
        if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
            raise RuntimeError(f"Source changed while hashing: {relative}")
        entries.append({"path": relative, "size": after.st_size, "sha256": digest, "source_mtime_ns": after.st_mtime_ns})
    result = {"format": FORMAT, "created_utc": datetime.now(timezone.utc).isoformat(), "scope": scope, "source_root": str(root), "buffer_bytes": BUFFER_BYTES, "file_count": len(entries), "total_bytes": sum(entry["size"] for entry in entries), "files": entries, "device_verified": False}
    write_json(output, result)
    print(f"Manifest complete: {len(entries)} files, {result['total_bytes']:,} bytes. Device transfer and device verification have not run.", flush=True)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-root", type=Path, required=True)
    parser.add_argument("--scope", choices=("basegame", "all"), default="basegame", help="basegame excludes the EP1 directory, EP1 marker and EP1 tweak database")
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        create_manifest(arguments.game_root, arguments.scope, arguments.output)
    except (OSError, RuntimeError) as error:
        print(f"Manifest failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
