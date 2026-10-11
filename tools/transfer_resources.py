#!/usr/bin/env python3
"""Resume bounded AFC transfers and full SHA-256 readback across USB reconnects."""
from __future__ import annotations

import argparse
import asyncio
import errno
import fcntl
import hashlib
import json
import os
import posixpath
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from resource_manifest import BUFFER_BYTES, FORMAT, MACHO_MAGICS, in_scope, valid_resource_path, write_json

REMOTE_ROOT = "Documents/GuestGame"
IO_BYTES = 1024 * 1024
HASH_CHECKPOINTS = {}
PREFIX_CHECKPOINTS = {}

def file_identity(stat):
    if not stat or not all(key in stat for key in ('st_ino','st_mtime','st_size')): return None
    return tuple(str(stat[key]) for key in ('st_ino','st_mtime','st_size'))


def load_manifest(path: Path, source_root: Path | None, scope: str) -> tuple[dict, Path, list[dict]]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("format") != FORMAT:
        raise RuntimeError("Unsupported resource manifest format")
    if scope == "all" and manifest.get("scope") != "all":
        raise RuntimeError("--scope all requires an all-scope manifest; a basegame manifest does not prove DLC completeness")
    root = (source_root or Path(manifest["source_root"])).resolve()
    entries = []
    seen = set()
    for entry in manifest["files"]:
        relative = entry["path"]
        if not valid_resource_path(relative) or relative in seen:
            raise RuntimeError(f"Unsafe or duplicate resource path: {relative}")
        seen.add(relative)
        if not in_scope(relative, scope):
            continue
        source = root / relative
        if not source.resolve().is_relative_to(root) or not source.is_file():
            raise RuntimeError(f"Resource missing or outside source root: {relative}")
        size = int(entry["size"])
        digest = entry["sha256"]
        if size < 0 or source.stat().st_size != size or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            raise RuntimeError(f"Manifest/source mismatch: {relative}")
        with source.open("rb") as file:
            if file.read(4) in MACHO_MAGICS:
                raise RuntimeError(f"Do not transfer original macOS executable as a resource: {relative}")
        entries.append(entry)
    if not entries:
        raise RuntimeError("No resources selected")
    return manifest, root, entries


async def remote_stat(afc, path: str):
    # Only a real AFC OBJECT_NOT_FOUND may be treated as absence. Permission,
    # disconnect and protocol errors must propagate, preserving resumability.
    from pymobiledevice3.exceptions import AfcFileNotFoundError
    try:
        return await afc.stat(path)
    except AfcFileNotFoundError:
        return None


async def remote_size(afc, path: str) -> int | None:
    stat = await remote_stat(afc, path)
    if stat and stat.get("st_ifmt") != "S_IFREG":
        raise RuntimeError(f"Remote resource/staging path is not a regular file: {path}")
    return int(stat["st_size"]) if stat else None


def progress(label: str, current: int, total: int, started: float, initial: int = 0) -> None:
    seconds = max(time.monotonic() - started, 0.001)
    print(f"{label}: {current:,}/{total:,} bytes, {(current-initial) / seconds / 1024 / 1024:.1f} MiB/s", flush=True)


async def remote_hash(afc, path: str, size: int, label: str) -> str:
    identity = file_identity(await remote_stat(afc,path))
    checkpoint = HASH_CHECKPOINTS.get(path)
    if not checkpoint or not identity or checkpoint['identity'] != identity or checkpoint['size'] != size:
        checkpoint = {'identity':identity,'size':size,'offset':0,'digest':hashlib.sha256()}
        HASH_CHECKPOINTS[path] = checkpoint
    digest = checkpoint['digest']
    read = checkpoint['offset']
    initial = read
    if read: print(f"Continue SHA-256 readback at {read:,} bytes; native inode/mtime/size unchanged: {path}",flush=True)
    handle = await afc.fopen(path, "r")
    started = last = time.monotonic()
    try:
        if read:await afc.fseek(handle,read,os.SEEK_SET)
        while read < size:
            chunk = await afc.fread(handle, min(IO_BYTES, size - read))
            if not chunk or len(chunk) > min(IO_BYTES, size - read):
                raise RuntimeError(f"Short or oversized AFC read at offset {read}: {path}")
            digest.update(chunk)
            read += len(chunk)
            checkpoint['offset'] = read
            now = time.monotonic()
            if now - last >= 10:
                progress(label, read, size, started, initial)
                last = now
    finally:
        await afc.fclose(handle)
    # Size is checked again because the game must be stopped during import.
    after = await remote_stat(afc,path)
    if not after or int(after['st_size']) != size or (identity and file_identity(after) != identity):
        HASH_CHECKPOINTS.pop(path,None)
        raise RuntimeError(f"Device file size changed while hashing: {path}")
    HASH_CHECKPOINTS.pop(path,None)
    return digest.hexdigest()


async def prefix_matches(afc, remote: str, source: Path, length: int) -> bool:
    identity = file_identity(await remote_stat(afc,remote))
    local = source.stat()
    key = (remote,str(source),length,local.st_mtime_ns,local.st_size)
    checkpoint = PREFIX_CHECKPOINTS.get(key)
    compared = checkpoint['offset'] if checkpoint and identity and checkpoint['identity'] == identity else 0
    initial = compared
    handle = await afc.fopen(remote, "r")
    checkpoint = {'identity':identity,'offset':compared};PREFIX_CHECKPOINTS[key] = checkpoint
    started = last = time.monotonic()
    try:
        with source.open("rb") as file:
            if compared:
                await afc.fseek(handle,compared,os.SEEK_SET);file.seek(compared)
                print(f"Continue resume-prefix comparison at {compared:,} bytes: {remote}",flush=True)
            while compared < length:
                count = min(IO_BYTES, length - compared)
                received = await afc.fread(handle, count)
                if len(received) != count or received != file.read(count):
                    PREFIX_CHECKPOINTS.pop(key,None)
                    return False
                compared += count
                checkpoint['offset'] = compared
                now = time.monotonic()
                if now - last >= 10:
                    progress("verify resume prefix " + remote, compared, length, started, initial)
                    last = now
    finally:
        await afc.fclose(handle)
    after = await remote_stat(afc,remote)
    PREFIX_CHECKPOINTS.pop(key,None)
    if identity and file_identity(after) != identity:raise RuntimeError('Device staging file changed during prefix verification: '+remote)
    return True


async def make_parents(afc, path: str) -> None:
    current = ""
    for part in posixpath.dirname(path).split("/"):
        current = posixpath.join(current, part)
        existing = await remote_stat(afc, current)
        if existing is None:
            await afc.makedirs(current)
        elif existing.get("st_ifmt") != "S_IFDIR":
            raise RuntimeError(f"Remote parent is not a directory: {current}")


async def copy_one(afc, root: Path, entry: dict, verify_only: bool) -> dict:
    relative, size, expected = entry["path"], int(entry["size"]), entry["sha256"]
    source = root / relative
    final = posixpath.join(REMOTE_ROOT, relative)
    partial, backup = final + ".cp2077-part", final + ".cp2077-old"
    final_size = await remote_size(afc, final)
    backup_size = await remote_size(afc, backup)
    if not verify_only and final_size is None and backup_size is not None:
        # Recover a disconnect that occurred between two native renames.
        await afc.rename(backup, final)
        final_size, backup_size = backup_size, None
    if final_size == size:
        print(f"verify existing {relative} (same size still requires SHA-256)", flush=True)
        actual = await remote_hash(afc, final, size, "readback " + relative)
        if actual == expected:
            if not verify_only and backup_size is not None:
                await afc.rm(backup)
            return {"path": relative, "size": size, "sha256": actual, "device_verified": True, "action": "existing_hash_verified"}
    if verify_only:
        raise RuntimeError(f"Missing, wrong-size or hash-mismatched device resource: {relative}")
    await make_parents(afc, final)
    offset = await remote_size(afc, partial)
    offset = offset or 0
    if offset > size or (offset and not await prefix_matches(afc, partial, source, offset)):
        print(f"Partial resource does not match local bytes; restart own staging file: {relative}", flush=True)
        await afc.rm(partial)
        offset = 0
    info = await afc.get_device_info()
    free = int(info.get("FSFreeBytes", 0))
    if free and free < size - offset:
        raise RuntimeError(f"Insufficient device space for {relative}: need {size-offset:,}, free {free:,} bytes")
    if offset < size:
        # r+ preserves a valid partial prefix; w creates/truncates only our
        # staging file. Native fseek selects its actual measured length.
        handle = await afc.fopen(partial, "r+" if offset else "w")
        transferred = offset
        started = last = time.monotonic()
        try:
            await afc.fseek(handle, offset, os.SEEK_SET)
            with source.open("rb") as file:
                file.seek(offset)
                while transferred < size:
                    chunk = file.read(min(IO_BYTES, size - transferred))
                    if not chunk:
                        raise RuntimeError(f"Local source became shorter during transfer: {relative}")
                    await afc.fwrite(handle, chunk, chunk_size=IO_BYTES)
                    transferred += len(chunk)
                    now = time.monotonic()
                    if now - last >= 10:
                        progress("write " + relative, transferred - offset, size - offset, started)
                        last = now
        finally:
            await afc.fclose(handle)
    if await remote_size(afc, partial) != size:
        raise RuntimeError(f"Device staging size mismatch: {relative}")
    # Before replacing an existing file, verify the whole staging copy first.
    # A first import needs only the final readback after rename; a mismatch
    # moves it back to staging without destroying any prior valid resource.
    if final_size is not None or backup_size is not None:
        staged_hash = await remote_hash(afc, partial, size, "verify staging " + relative)
        if staged_hash != expected:
            raise RuntimeError(f"Device staging SHA-256 mismatch: {relative}; staging retained for diagnosis")
    if backup_size is not None:
        # A stale backup is only removed after a full verified new stage exists.
        await afc.rm(backup)
    if final_size is not None:
        await afc.rename(final, backup)
    try:
        await afc.rename(partial, final)
        actual = await remote_hash(afc, final, size, "verify final " + relative)
        if actual != expected:
            raise RuntimeError(f"Device final SHA-256 mismatch after rename: {relative}")
    except BaseException:
        # Roll back when transport is available; if disconnected, the next run
        # recovers .cp2077-old before inspecting the resource.
        try:
            if await remote_size(afc, final) is not None:
                await afc.rename(final, partial)
            if await remote_size(afc, backup) is not None:
                await afc.rename(backup, final)
        except Exception:
            pass
        raise
    if await remote_size(afc, backup) is not None:
        await afc.rm(backup)
    return {"path": relative, "size": size, "sha256": actual, "device_verified": True, "action": "resumed_and_verified" if offset else "transferred_and_verified", "resumed_bytes": offset}


async def transfer(arguments, root: Path, entries: list[dict], report: dict) -> None:
    try:
        from pymobiledevice3.lockdown import create_using_usbmux
        from pymobiledevice3.services.house_arrest import HouseArrestService
        from pymobiledevice3.exceptions import (ConnectionTerminatedError, ConnectionFailedError,
                                               DeviceNotFoundError, NoDeviceConnectedError)
    except ImportError as error:
        raise RuntimeError("Install tools/requirements-resources.txt in the project resources-venv first") from error
    print("Connect by USB, unlock the iPhone, keep this application stopped during transfer.", flush=True)
    pairing_cache = Path(__file__).resolve().parents[1] / "work" / "pairing-cache"
    class TransferHouseArrest(HouseArrestService):
        async def _dispatch_packet(self, *args, **kwargs):
            # In pinned 11.26.0 a send failure can leave the registered Future
            # already failed by the reader. Consume only that request's Future;
            # the real transport exception still reaches the reconnect loop.
            waiting = tuple(self._afc_pending.values())
            try:
                return await super()._dispatch_packet(*args, **kwargs)
            except BaseException:
                for future in waiting:
                    if future.done() and not future.cancelled(): future.exception()
                    elif not future.done(): future.cancel()
                raise

        async def _send_and_wait(self, *args, **kwargs):
            if self._afc_terminated.is_set(): raise ConnectionTerminatedError()
            async with asyncio.timeout(60):
                return await super()._send_and_wait(*args, **kwargs)

    transport_errors = (ConnectionError, TimeoutError, asyncio.IncompleteReadError,
                        ConnectionTerminatedError, ConnectionFailedError,
                        DeviceNotFoundError, NoDeviceConnectedError)
    index = failures = 0
    while index < len(entries):
        try:
            async with asyncio.timeout(30):
                lockdown = await create_using_usbmux(serial=arguments.device, connection_type="USB", autopair=False, pairing_records_cache_folder=pairing_cache)
            async with lockdown:
                async with asyncio.timeout(30):
                    afc = await TransferHouseArrest.create(lockdown, arguments.bundle_id, documents_only=False)
                async with afc:
                    report["container_opened"] = True
                    report["status"] = "transferring"
                    while index < len(entries):
                        entry = entries[index]
                        report["current_file"] = entry["path"]
                        write_json(arguments.report, report)
                        print(f"resource [{index+1}/{len(entries)}] {entry['path']}", flush=True)
                        result = await copy_one(afc, root, entry, arguments.verify_only)
                        report["files"].append(result)
                        report["verified_files"] = len(report["files"])
                        report["verified_bytes"] = sum(file["size"] for file in report["files"])
                        write_json(arguments.report, report)
                        index += 1
                        failures = 0
        except Exception as error:
            transient = isinstance(error, transport_errors) or (isinstance(error, OSError) and error.errno in {
                errno.ECONNRESET, errno.ECONNABORTED, errno.ETIMEDOUT, errno.ENOTCONN, errno.ENODEV, errno.EPIPE})
            if not transient: raise
            failures += 1
            report["connection_restarts"] = report.get("connection_restarts", 0) + 1
            report["status"] = "reconnecting"
            message = str(error)
            if arguments.device: message = message.replace(arguments.device, "<device>")
            report["last_transport_error"] = f"{type(error).__name__}: {message}"
            write_json(arguments.report, report)
            if failures > arguments.max_reconnects: raise
            delay = min(30, 2 ** min(failures, 5))
            print(f"USB/AFC connection interrupted. Reconnect {failures}/{arguments.max_reconnects} in {delay}s; keep iPhone unlocked. The current staging file will be byte-verified before resume.", flush=True)
            await asyncio.sleep(delay)
    report["status"] = "complete"
    report["device_verified"] = report["verified_files"] == len(entries)
    report.pop("current_file", None)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--game-root", type=Path)
    parser.add_argument("--scope", choices=("basegame", "all"), default="basegame")
    parser.add_argument("--bundle-id", help="Actual installed app bundle identifier; required except --dry-run")
    parser.add_argument("--device", help="Optional USB device selector; omitted when only one iPhone is connected")
    parser.add_argument("--dry-run", action="store_true", help="Check local manifest and list transfer size without connecting to iPhone")
    parser.add_argument("--verify-only", action="store_true", help="Read device resources and verify SHA-256 without transferring")
    parser.add_argument("--report", type=Path, default=Path("resource-transfer-report.json"))
    parser.add_argument("--max-reconnects",type=int,default=12,help="Maximum consecutive transport reconnections per file")
    arguments = parser.parse_args()
    if not arguments.dry_run and not arguments.bundle_id:
        parser.error("--bundle-id is required for actual container access")
    if arguments.dry_run and arguments.verify_only:
        parser.error("--dry-run and --verify-only are mutually exclusive")
    if arguments.max_reconnects < 0:parser.error("--max-reconnects must be non-negative")
    lock = None
    if not arguments.dry_run:
        arguments.report.parent.mkdir(parents=True,exist_ok=True)
        lock=arguments.report.with_suffix('.lock').open('a')
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:
            print("Another resource operation is running. Wait for it to finish before starting again.",file=sys.stderr)
            lock.close();return 1
    report = {"format": "CPResourceTransferReportV1", "created_utc": datetime.now(timezone.utc).isoformat(), "scope": arguments.scope, "status": "starting", "buffer_bytes": BUFFER_BYTES, "io_chunk_bytes":IO_BYTES, "remote_root": REMOTE_ROOT, "container_opened": False, "device_verified": False, "verified_files": 0, "verified_bytes": 0, "files": []}
    try:
        _, root, entries = load_manifest(arguments.manifest, arguments.game_root, arguments.scope)
        report.update({"expected_files": len(entries), "expected_bytes": sum(file["size"] for file in entries)})
        print(f"Selected {len(entries)} files, {report['expected_bytes']:,} bytes, scope={arguments.scope}.", flush=True)
        if arguments.dry_run:
            report["status"] = "dry_run_only"
            print("Dry run complete. No device connection, transfer or device SHA-256 verification performed.", flush=True)
        else:
            asyncio.run(transfer(arguments, root, entries, report))
            print(f"All {report['verified_files']} device files verified by full SHA-256 readback.", flush=True)
    except (Exception, KeyboardInterrupt) as error:
        report["status"] = "interrupted" if isinstance(error, KeyboardInterrupt) else "failed"
        # Device IDs, pairing records and certificates are deliberately absent
        # from reports and error diagnostics included with source deliverables.
        message = str(error)
        if arguments.device:
            message = message.replace(arguments.device, "<device>")
        report["error"] = f"{type(error).__name__}: {message}"
        print(f"Resource operation failed: {report['error']}", file=sys.stderr)
        write_json(arguments.report, report)
        return 1
    write_json(arguments.report, report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
