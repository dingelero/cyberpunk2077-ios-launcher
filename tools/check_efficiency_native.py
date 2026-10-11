#!/usr/bin/env python3
"""Native host regression tests; never launches or installs the iPhone game."""
import argparse,json,subprocess
from pathlib import Path
from common import ROOT,run,env,write_json

def check(settings,destination):
    destination=Path(destination);destination.mkdir(parents=True,exist_ok=True)
    binary=destination/'check-efficiency-native'
    sources=[ROOT/'tools/check_efficiency_native.m',ROOT/'App/compat/PathStrings.m',ROOT/'App/compat/GuestPaths.m',
        ROOT/'App/GameJSON.m',ROOT/'App/GamePacing.m']
    run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-fmodules','-O2','-I',ROOT/'App','-I',ROOT/'App/compat',
        *sources,'-framework','Foundation','-framework','Metal','-o',binary])
    result=subprocess.run([str(binary),str(settings)],env=env(),text=True,capture_output=True,timeout=60)
    (destination/'native.stderr').write_text(result.stderr)
    if result.returncode:raise RuntimeError('Native regression failed: '+result.stderr[-8000:])
    reports=json.loads(result.stdout)
    reports['scope']='Native Mac component regressions only; iPhone sustained frame rate, HDR and game correctness require user QA.'
    write_json(destination/'result.json',reports)
    print(json.dumps(reports,ensure_ascii=False,indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('settings',type=Path);p.add_argument('--output',type=Path,default=ROOT/'work/performance/v4-native')
    a=p.parse_args();check(a.settings,a.output)
