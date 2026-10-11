#!/usr/bin/env python3
"""Build a version-locked experimental IPA from the user's original Steam game."""
import argparse, subprocess, sys
from pathlib import Path
from common import ROOT, env

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform',choices=['ios','iossim'],default='ios')
    parser.add_argument('--output',type=Path,default=ROOT/'dist/Cyberpunk2077-iPhone16ProMax-experimental.ipa')
    args=parser.parse_args()
    steps=[('audit.py',[]),('fetch_dependencies.py',[]),
           ('prepare.py',['--platform',args.platform]),
           ('patch_memory_budget.py',['--platform',args.platform]),
           ('performance_profile.py',['--platform',args.platform]),
           ('build_compat.py',['--platform',args.platform]),
           ('build_curl.py',['--platform',args.platform]),
           ('build.py',['--platform',args.platform])]
    if args.platform=='ios':steps.append(('package.py',[str(args.output)]))
    for script,parameters in steps:
        print('BUILD_STEP '+script,flush=True)
        subprocess.run([sys.executable,str(ROOT/'tools'/script),*parameters],cwd=ROOT,env=env(),check=True)
    print('Experimental build complete. Game rendering and physical-device gameplay require runtime verification.')

if __name__=='__main__':main()
