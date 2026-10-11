#!/bin/bash
# Double-click from Finder after signing and installing the companion IPA.
set -u
command_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
workspace_dir="$(cd -- "${command_dir}/.." && pwd -P)/work/resource-import"
/bin/mkdir -p "${workspace_dir}/logs"
log_path="${workspace_dir}/logs/import-$(/bin/date +%Y%m%d-%H%M%S).log"
pause_at_end=1
for argument in "$@"; do
    if [[ "$argument" == "--non-interactive" ]]; then pause_at_end=0; fi
done
exec > >(/usr/bin/tee -a "$log_path") 2>&1
finish() {
    result=$?
    trap - EXIT
    echo
    echo "操作已结束，退出码：${result}"
    echo "日志保存在：${log_path}"
    if [[ "$pause_at_end" == "1" && -t 0 ]]; then
        read -r -p "按回车关闭此窗口。" ignored
    fi
    exit "$result"
}
trap finish EXIT

python_binary=""
python_candidates=("${CP_IMPORT_PYTHON:-}" "/opt/homebrew/bin/python3" "/usr/local/bin/python3" "$(command -v python3 || true)" "/usr/bin/python3")
for candidate in "${python_candidates[@]}"; do
    if [[ -n "$candidate" && -x "$candidate" ]] && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
        python_binary="$candidate"
        break
    fi
done
if [[ -z "$python_binary" ]]; then
    echo "未找到 Python 3.11 或更新版本。安装 Python 后，再双击此文件。"
    exit 1
fi

bootstrap_path="${workspace_dir}/bootstrap.py"
/bin/cat > "$bootstrap_path" <<'PYTHON_BOOTSTRAP'
from __future__ import annotations
import argparse
import asyncio
import importlib.metadata
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path
from datetime import datetime, timezone
from zipfile import ZipFile, BadZipFile

VERSION = "11.26.0"
DEFAULT_BUNDLE = "local.cyberpunk.ios.rebuilt"
SOURCE_NAME = "Cyberpunk2077-iOS-rebuild-source.zip"
REQUIRED = (
    "tools/transfer_resources.py",
    "tools/resource_manifest.py",
    "tools/requirements-resources.txt",
    "evidence/resources-basegame-manifest.json",
    "evidence/resources-all-manifest.json",
)

def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)

def stage_tools(arguments):
    destination = arguments.work_dir / "source"
    if arguments.source_dir:
        source = arguments.source_dir.resolve()
        for relative in REQUIRED:
            if not (source / relative).is_file():
                raise RuntimeError(f"源码目录缺少 {relative}")
        return source
    archive = arguments.command_dir / SOURCE_NAME
    if not archive.is_file():
        raise RuntimeError(f"请将 {SOURCE_NAME} 放在此 .command 文件旁边。未执行任何设备导入。")
    with ZipFile(archive) as zipfile:
        names = set(zipfile.namelist())
        prefix = "cp2077-port/"
        for relative in REQUIRED:
            member = prefix + relative
            if member not in names:
                raise RuntimeError(f"源码 ZIP 缺少 {member}")
            info = zipfile.getinfo(member)
            if info.file_size > 10 * 1024 * 1024:
                raise RuntimeError(f"源码文件异常过大：{member}")
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_name(target.name + ".tmp")
            temporary.write_bytes(zipfile.read(member))
            temporary.replace(target)
    if (destination / "tools/requirements-resources.txt").read_text().strip() != f"pymobiledevice3=={VERSION}":
        raise RuntimeError("源码依赖版本与此导入工具不匹配；未执行设备导入。")
    return destination

def package_version(python):
    result = subprocess.run([str(python), "-c", "import importlib.metadata; print(importlib.metadata.version('pymobiledevice3'))"], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return result.stdout.strip() if result.returncode == 0 else None

def dependency_python(arguments, source):
    if package_version(sys.executable) == VERSION:
        return Path(sys.executable)
    environment = arguments.work_dir / "resources-venv"
    python = environment / "bin/python"
    if not python.is_file():
        print("首次运行：创建独立 Python 环境。", flush=True)
        subprocess.run([sys.executable, "-m", "venv", str(environment)], check=True)
    if package_version(python) != VERSION:
        print(f"安装固定依赖 pymobiledevice3 {VERSION}；不更改系统 Python。", flush=True)
        subprocess.run([str(python), "-m", "pip", "install", "-r", str(source / "tools/requirements-resources.txt")], check=True)
    if package_version(python) != VERSION:
        raise RuntimeError("依赖版本核验失败。")
    return python

async def device_preflight(arguments):
    from pymobiledevice3.usbmux import list_devices
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.services.installation_proxy import InstallationProxyService
    candidates = [device for device in await list_devices() if device.connection_type == "USB"]
    if not candidates:
        raise RuntimeError("没有发现 USB iPhone / iPad。连接数据线并解锁；首次连接请先在 Finder 和手机上完成信任。")
    phones = []
    for device in candidates:
        arguments.selected_device = device.serial
        async with await create_using_usbmux(serial=device.serial, connection_type="USB", autopair=False, pairing_records_cache_folder=arguments.work_dir / "pairing-cache") as lockdown:
            if lockdown.all_values.get("DeviceClass") in ("iPhone", "iPad"):
                phones.append(device)
    if len(phones) != 1:
        raise RuntimeError("请只连接一台要导入的 iPhone / iPad，再运行此工具。")
    device = phones[0]
    arguments.selected_device = device.serial
    async with await create_using_usbmux(serial=device.serial, connection_type="USB", autopair=False, pairing_records_cache_folder=arguments.work_dir / "pairing-cache") as lockdown:
        async with InstallationProxyService(lockdown) as installation:
            bundle = arguments.bundle_id
            applications = await installation.get_apps(application_type="User", bundle_identifiers=[bundle])
            if bundle not in applications and bundle == DEFAULT_BUNDLE:
                # Some normal signing tools append the team identifier. Match
                # only this app's original identifier and a single installed
                # candidate; never choose an unrelated game automatically.
                all_apps = await installation.get_apps(application_type="User")
                matches = [identifier for identifier in all_apps
                           if identifier.startswith(DEFAULT_BUNDLE + ".")]
                if len(matches) == 1:
                    bundle = matches[0]
                    applications = {bundle: all_apps[bundle]}
                    print(f"签名工具已追加 ID 后缀，自动使用已安装应用：{bundle}", flush=True)
            if bundle not in applications:
                print(f"未找到已安装应用：{bundle}", flush=True)
                if not arguments.non_interactive and sys.stdin.isatty():
                    changed = input("如果签名时更改了 Bundle ID，请输入实际值；直接回车则退出：").strip()
                    if changed:
                        bundle = changed
                        applications = await installation.get_apps(application_type="User", bundle_identifiers=[bundle])
                if bundle not in applications:
                    raise RuntimeError("目标 IPA 尚未安装，或 Bundle ID 不匹配。请先用自己的证书签名并安装 IPA。未传输资源。")
            arguments.bundle_id = bundle
            print(f"已发现 USB iPhone / iPad，目标应用已安装：{bundle}", flush=True)
    return device.serial

def local_game_root(arguments):
    root = arguments.game_root or Path.home() / "Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"
    if not root.is_dir() and not arguments.non_interactive and sys.stdin.isatty():
        value = input("未找到默认 Steam 游戏目录，请将正版 Cyberpunk 2077 文件夹拖入此窗口并按回车：").strip()
        parsed = shlex.split(value)
        if len(parsed) == 1:
            root = Path(parsed[0])
    if not root.is_dir():
        raise RuntimeError("正版游戏目录不存在；未执行资源导入。")
    return root.resolve()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--command-dir", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--source-dir", type=Path)
    parser.add_argument("--game-root", type=Path)
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE)
    parser.add_argument("--scope", choices=("basegame", "all"))
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--non-interactive", action="store_true")
    parser.add_argument("--dependencies-ready", action="store_true", help=argparse.SUPPRESS)
    arguments = parser.parse_args()
    arguments.selected_device = None
    result = {"created_utc": datetime.now(timezone.utc).isoformat(), "device_verified": False, "resource_transfer_performed": False, "status": "starting"}
    preflight_report = arguments.work_dir / "preflight-report.json"
    try:
        source = stage_tools(arguments)
        root = local_game_root(arguments)
        if not arguments.dry_run:
            python = dependency_python(arguments, source)
            # A venv interpreter commonly symlinks to the same base Python.
            # Its module environment, rather than resolved executable path,
            # determines whether we must restart in the prepared venv.
            if package_version(sys.executable) != VERSION:
                if arguments.dependencies_ready:
                    raise RuntimeError("独立 Python 环境启动后未找到固定版本依赖。")
                return subprocess.run([str(python), __file__, *sys.argv[1:], "--dependencies-ready"]).returncode
            asyncio.run(device_preflight(arguments))
            result["iphone_detected"] = True
            result["application_installed"] = True
            result["bundle_id"] = arguments.bundle_id
            if arguments.preflight_only:
                result["status"] = "preflight_only"
                save(preflight_report, result)
                print("安装预检通过。此模式未传输资源，也没有验证设备资源哈希。", flush=True)
                return 0
        scope = arguments.scope
        if scope is None and not arguments.non_interactive and not arguments.dry_run and sys.stdin.isatty():
            choice = input("资源范围：回车导入本体约 70 GB；输入 all 导入全部约 96 GB：").strip().lower()
            if choice not in ("", "basegame", "all"):
                raise RuntimeError("资源范围只能为 basegame 或 all。")
            scope = choice or "basegame"
        scope = scope or "basegame"
        manifest = source / "evidence" / f"resources-{scope}-manifest.json"
        tool = source / "tools/transfer_resources.py"
        report = arguments.work_dir / "resource-transfer-report.json"
        command = [sys.executable, str(tool), "--manifest", str(manifest), "--game-root", str(root), "--scope", scope, "--report", str(report)]
        if arguments.dry_run:
            command += ["--dry-run"]
        else:
            command += ["--bundle-id", arguments.bundle_id, "--device", arguments.selected_device]
            print("开始资源导入；游戏请保持关闭。中断后重新双击可验证断点并续传。", flush=True)
        status = subprocess.run(command).returncode
        if status:
            result["status"] = "transfer_or_local_check_failed"
            save(preflight_report, result)
            raise RuntimeError(f"资源工具返回 {status}；完整进度和错误保留在 {report}")
        transfer_report = json.loads(report.read_text(encoding="utf-8"))
        if arguments.dry_run:
            result["status"] = "dry_run_only"
            save(preflight_report, result)
            print("本机预检完成；未连接手机、未传输资源、未验证设备哈希。", flush=True)
        elif transfer_report.get("status") == "complete" and transfer_report.get("device_verified") is True:
            result.update({"status": "complete", "resource_transfer_performed": True, "device_verified": True})
            save(preflight_report, result)
            print(f"资源导入完成：{transfer_report['verified_files']} 个文件，均已完整读回并核对 SHA-256。游戏运行仍需另行验证。", flush=True)
        else:
            raise RuntimeError("资源报告未证明完整设备哈希验证；不能标记导入完成。")
        return 0
    except (Exception, KeyboardInterrupt) as error:
        result["status"] = "interrupted" if isinstance(error, KeyboardInterrupt) else "failed"
        message = str(error)
        if arguments.selected_device:
            message = message.replace(arguments.selected_device, "<device>")
        result["error"] = f"{type(error).__name__}: {message}"
        save(preflight_report, result)
        print(f"导入未完成：{result['error']}", file=sys.stderr, flush=True)
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
PYTHON_BOOTSTRAP
/usr/bin/caffeinate -i "$python_binary" "$bootstrap_path" --command-dir "$command_dir" --work-dir "$workspace_dir" "$@"
exit "$?"
