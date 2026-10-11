#!/bin/bash
set -u
command_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
python_binary=""
for candidate in "${CP_IMPORT_PYTHON:-}" /opt/homebrew/bin/python3 /usr/local/bin/python3 "$(command -v python3 || true)" /usr/bin/python3; do
    if [[ -n "$candidate" && -x "$candidate" ]] && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)' >/dev/null 2>&1; then
        python_binary="$candidate"; break
    fi
done
if [[ -z "$python_binary" ]]; then
    echo "请安装 Python 3.11 或更新版本。"
    exit 1
fi
echo "请先保存游戏；保持一台 iPhone / iPad USB 连接并解锁。Mac 需安装含 devicectl 的 Xcode。"
echo "此工具只读取已保存的性能记录，不启动、关闭或更新游戏。"
"$python_binary" - "$command_dir" <<'PYTHON_EXPORT'
from pathlib import Path
from datetime import datetime
from zipfile import ZipFile
import subprocess,sys

try:
    directory=Path(sys.argv[1])
    archive=directory/'Cyberpunk2077-iOS-rebuild-source.zip'
    project=directory.parent/'work'/'launcher-logs'/'source'
    with ZipFile(archive) as package:
        for relative in ('tools/collect_mobile_trace.py','tools/probe_device.py','tools/common.py','config.example.json'):
            member='cp2077-port/'+relative
            if package.getinfo(member).file_size>1024*1024:
                raise ValueError('源码文件异常过大：'+member)
            target=project/relative;target.parent.mkdir(parents=True,exist_ok=True)
            temporary=target.with_name(target.name+'.tmp');temporary.write_bytes(package.read(member));temporary.replace(target)
    destination=directory.parent/'work'/'launcher-logs'/datetime.now().strftime('%Y%m%d-%H%M%S')
    status=subprocess.run([sys.executable,str(project/'tools/collect_mobile_trace.py'),'--output',str(destination)]).returncode
except Exception as error:
    print('读取失败：'+str(error),file=sys.stderr);status=1
sys.exit(status)
PYTHON_EXPORT
task_trace_status=$?
echo "读取结束，退出码：$task_trace_status。"
if [[ -t 0 ]]; then read -r -p "按回车关闭。" task_trace_key; fi
exit "$task_trace_status"
