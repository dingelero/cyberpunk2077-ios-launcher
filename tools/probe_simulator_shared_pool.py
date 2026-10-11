#!/usr/bin/env python3
"""Exercise native simulator GPU copies through the diagnostic Shared buffer pool."""
import argparse,json,subprocess
from common import ROOT,env,run,write_json
from build_compat import flags

def probe(device):
    directory=ROOT/'work/shared-pool-probe';directory.mkdir(parents=True,exist_ok=True)
    binary=directory/'shared-pool-probe';logs=ROOT/'evidence/shared-pool';logs.mkdir(parents=True,exist_ok=True)
    base,_,_=flags('iossim')
    run(base+['-I',ROOT/'App/compat',ROOT/'App/probes/SimulatorSharedPoolProbe.m',ROOT/'App/compat/SimulatorSharedBufferPool.m',
        '-framework','Foundation','-framework','Metal','-o',binary],logfile=logs/'build.log')
    run(['codesign','--force','--sign','-',binary])
    result=subprocess.run(['xcrun','simctl','spawn',device,binary],env=env(),capture_output=True,text=True,timeout=60)
    (logs/'runtime.stdout').write_text(result.stdout);(logs/'runtime.stderr').write_text(result.stderr)
    report=json.loads(result.stdout) if result.stdout.strip().startswith('{') else {'launchError':result.stderr[-2000:]}
    report['exitCode']=result.returncode;write_json(logs/'runtime.json',report)
    print(json.dumps(report,indent=2))
    if result.returncode:raise RuntimeError('Shared pool native simulator probe failed')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--device',required=True);probe(parser.parse_args().device)
