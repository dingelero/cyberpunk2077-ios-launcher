"""Shared project paths and explicit command execution."""
import hashlib, json, os, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def config():
    local = ROOT / 'config.local.json'
    result = json.loads((local if local.exists() else ROOT / 'config.example.json').read_text())
    result['game_root'] = str(Path(result['game_root']).expanduser())
    developer = result.get('developer_dir') or os.environ.get('DEVELOPER_DIR')
    if not developer:
        beta = Path('/Applications/Xcode-beta.app/Contents/Developer')
        developer = str(beta) if beta.is_dir() else subprocess.check_output(['xcode-select','-p'],text=True).strip()
    result['developer_dir'] = developer
    return result

def env():
    result = os.environ.copy()
    result['DEVELOPER_DIR'] = config()['developer_dir']
    return result

def run(argv, *, cwd=None, logfile=None):
    result = subprocess.run(list(map(str, argv)), cwd=cwd, env=env(), text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if logfile:
        Path(logfile).parent.mkdir(parents=True, exist_ok=True)
        Path(logfile).write_text(result.stdout)
    if result.returncode:
        raise RuntimeError(f'Command failed ({result.returncode}): {argv}\n{result.stdout[-12000:]}')
    return result.stdout

def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda: f.read(4 * 1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def write_json(path, value):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

def output(platform):
    return ROOT / 'build' / platform
