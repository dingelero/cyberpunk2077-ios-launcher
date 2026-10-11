"""Native mobile instruction / settings / touch geometry regression checks."""
import json,struct,subprocess
from pathlib import Path
from common import ROOT,run,env,write_json
from mobile_engine_patch import apply,BASE_TEXT,TEXT_SHA256,ADDRESS,OLD,NEW
from game_streaming_patch import apply as streaming
from macho import text_hash,commands

def check():
    folder=ROOT/'work/performance/universal-v5-native';folder.mkdir(parents=True,exist_ok=True)
    current=(ROOT/'build/ios/prepared/CyberpunkGuest.dylib').read_bytes()
    base=bytearray(current);struct.pack_into('<I',base,ADDRESS-0x100000000,OLD)
    if text_hash(base)!=BASE_TEXT:raise ValueError('Mobile reversal did not restore v4')
    result,report=apply(base)
    if result!=current or text_hash(result)!=TEXT_SHA256:raise ValueError('Unexpected whole-file patch output')
    failed,_=streaming(base);recovered,recovery=apply(failed)
    if recovered!=current:raise ValueError('Failed v1 rollback did not produce current mobile patch')
    if apply(current)[0]!=current:raise ValueError('Patch not idempotent')
    uuid_at=next(p+8 for p,c,s in commands(base) if c==0x1b)
    for at in [uuid_at,0x1076204]:
        damaged=bytearray(base);damaged[at]^=1
        try:apply(damaged)
        except ValueError:pass
        else:raise ValueError('Unrecognized input accepted')
    asm=folder/'native-range.S';parts=['.text','.p2align 2']
    for name,binary in [('before',base),('after',current)]:
        words=struct.unpack_from('<III',binary,ADDRESS-0x100000000)
        parts += [f'.globl _cp_mobile_{name}',f'_cp_mobile_{name}:',*[f'.long {hex(w)}' for w in words],'.long 0xd65f03c0']
    asm.write_text('\n'.join(parts)+'\n')
    executable=folder/'check-mobile-native'
    run(['xcrun','--sdk','macosx','clang','-O2','-fobjc-arc','-fmodules','-I',ROOT/'App','-I',ROOT/'App/compat',
        ROOT/'tools/check_mobile_native.m',ROOT/'App/GameEngineAudit.m',ROOT/'App/GameJSON.m',ROOT/'App/GamePacing.m',asm,
        '-framework','Foundation','-o',executable])
    settings=ROOT/'work/device-startup/20261011-streaming-v1-feedback/UserSettings.json'
    checked=subprocess.run([str(executable),str(settings)],env=env(),capture_output=True,text=True,timeout=60)
    (folder/'native.stderr').write_text(checked.stderr)
    if checked.returncode:raise RuntimeError(checked.stderr)
    native=json.loads(checked.stdout)
    write_json(ROOT/'evidence/universal-v5-engine-components.json',{'native':native,'enginePatch':report,
        'failedV1RollbackChecked':True,'byteExactReversalToV4':True,'unsupportedInputsRejected':True,'gameplayVerified':False})
    print(json.dumps(native,indent=2))
if __name__=='__main__':check()
