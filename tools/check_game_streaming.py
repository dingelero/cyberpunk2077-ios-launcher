#!/usr/bin/env python3
"""Test version locking, reversibility and actual ARM64 parameter store words."""
import json,struct,subprocess
from pathlib import Path
from common import ROOT,config,env,run,write_json
from game_streaming_patch import apply,offset,TEXT_PAIRS,PATCHES
from macho import commands,text_hash

def check():
    original=Path(config()['game_root'])/'Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077'
    source=original.read_bytes();patched,receipt=apply(source)
    reverse,_=apply(patched,True)
    if reverse!=source:raise ValueError('Native executable reversal not byte-exact')
    twice,_=apply(patched)
    if twice!=patched:raise ValueError('Reapplication changed the image')
    permitted={offset(source,a)+i for a,_,_ in PATCHES for i in range(4)}
    if any(a!=b and i not in permitted for i,(a,b) in enumerate(zip(source,patched))):raise ValueError('Unexpected executable byte change')
    corrupt=bytearray(source);corrupt[offset(source,PATCHES[0][0])]^=1
    uuid_bad=bytearray(source)
    for at,kind,_ in commands(uuid_bad):
        if kind==0x1b:uuid_bad[at+8]^=1;break
    for bad in (corrupt,uuid_bad):
        try:apply(bad)
        except ValueError:pass
        else:raise ValueError('Incorrect version accepted')
    destination=ROOT/'work/performance/game-streaming-v1-native';destination.mkdir(parents=True,exist_ok=True)
    asm=['.text','.p2align 2']
    for name,blob in [('before',source),('after',patched)]:
        asm += [f'.globl _cp_defaults_{name}',f'_cp_defaults_{name}:','stp x22, x24, [sp, #-16]!','mov x22, x0']
        for vm in [0x1021bc7ec,0x1021bc7f0,0x1021bc7f4]:asm.append(f'.long {struct.unpack_from("<I",blob,offset(blob,vm))[0]:#x}')
        asm += ['mov x22, x1']
        for vm in [0x1021bc834,0x1021bc838]:asm.append(f'.long {struct.unpack_from("<I",blob,offset(blob,vm))[0]:#x}')
        asm += ['mov x22, x2']
        for vm in [0x1021bc878,0x1021bc87c,0x1021bc880]:asm.append(f'.long {struct.unpack_from("<I",blob,offset(blob,vm))[0]:#x}')
        asm += ['ldp x22, x24, [sp], #16','ret']
    asm += ['.globl _cp_native_limit','_cp_native_limit:','stp x21, x30, [sp, #-16]!','mov w21, w0','mov w0, w1']
    for vm in range(0x1021bab94,0x1021baba8,4):asm.append(f'.long {struct.unpack_from("<I",source,offset(source,vm))[0]:#x}')
    asm += ['mov w0, w8','ldp x21, x30, [sp], #16','ret']
    assembly=destination/'native-instructions.S';assembly.write_text('\n'.join(asm)+'\n');binary=destination/'check-native'
    run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-O2','-I',ROOT/'App',ROOT/'tools/check_game_streaming_native.m',ROOT/'App/GameEngineAudit.m',assembly,'-framework','Foundation','-o',binary])
    result=subprocess.run([str(binary)],env=env(),text=True,capture_output=True,timeout=30)
    if result.returncode:raise RuntimeError('Native instruction test failed: '+result.stderr)
    report={'patch':receipt,'nativeInstructions':json.loads(result.stdout),'reverseByteExact':True,
        'wrongUUIDAndCodeRejected':True,'onlyTwoInstructionWordsChanged':True,'originalSourceNotWritten':True}
    write_json(ROOT/'evidence/game-streaming-v1-components.json',report);print(json.dumps(report,indent=2))

if __name__=='__main__':check()
