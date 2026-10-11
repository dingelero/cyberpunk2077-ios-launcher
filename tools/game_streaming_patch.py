#!/usr/bin/env python3
"""Version-locked engine instruction patch; writes a new file, never the source.

This changes native resource-loader defaults, not gameplay data or renderer
quality. A native INI override can still replace the defaults. Runtime frame
time improvement and correctness require iPhone gameplay QA.
"""
import argparse, json, os, struct, tempfile
from pathlib import Path
from macho import inspect, sections, text_hash

VERSION = 'game-streaming-v1'
UUID = 'A6656ADC-FBE2-36A4-9B9D-B4A9DE645089'
TEXT_PAIRS = {
    'd7d424a91c64d30cf3fa34cbd32a7948d4d77836bb8d8b3c8619e4f23ad0645a':
    '261b415062879f860c00c5459711d5f91a9319c11d46fa0f725138d535270675',
    '271b77fc4c2f60e1d15897f3a4b494f8725fca98bd731f9162c4beed0edc4bdf':
    '4261c095d35631e15be75777a08ca0045d87ea3ceac1f6dcd1e3436ae6b73bd8',
}
PATCHES = (
    # w24 is shared by BOTH StreamMaxLoadingThreads and
    # FloodMinNonLoadingThreads. Intentionally raise both defaults to 3:
    # one more streaming token, and one more non-loading worker reserved
    # during flood loading. Native worker-count clamps remain intact.
    (0x1021bc7ec, 0x52800058, 0x52800078),
    # Dedicated decompression buffer: 1 -> 4 MiB per buffer. No global
    # streaming-cache inflation; allocation, bounds checks and lifetime stay.
    (0x1021bc878, 0x52a00208, 0x52a00808),
)

def offset(data, address):
    for section in sections(data):
        if section['name']=='__text' and section['address']<=address<section['address']+section['size']:
            return section['offset']+address-section['address']
    raise ValueError('Instruction outside executable section')

def apply(data, reverse=False):
    if inspect(data)['uuid'] != UUID:
        raise ValueError('Unsupported game UUID; fixed offsets refused')
    pairs = {v:k for k,v in TEXT_PAIRS.items()} if reverse else TEXT_PAIRS
    before=text_hash(data)
    if before in pairs.values():
        original,_ = apply(data,not reverse)
        _,report = apply(original,reverse)
        report.update({'alreadyApplied':True,'beforeTextSHA256':before,'afterTextSHA256':before,'instructionsAppliedThisCall':0})
        return bytes(data),report
    if before not in pairs:
        raise ValueError('Unsupported executable instruction hash; fixed offsets refused')
    result=bytearray(data);changes=[]
    for address,old,new in PATCHES:
        if reverse:old,new=new,old
        at=offset(data,address)
        if struct.unpack_from('<I',data,at)[0] != old:
            raise ValueError('Instruction precondition failed at '+hex(address))
        struct.pack_into('<I',result,at,new)
        changes.append({'virtualAddress':hex(address),'fileOffset':hex(at),
                        'before':hex(old),'after':hex(new)})
    after=text_hash(result)
    if after!=pairs[before]:raise ValueError('Unexpected patched instruction hash')
    return bytes(result), {'version':VERSION,'uuid':UUID,'reversed':reverse,
        'beforeTextSHA256':before,'afterTextSHA256':after,'instructions':changes,'instructionsAppliedThisCall':2,
        'nativeDefaults':{'StreamMaxLoadingThreads':{'before':2,'after':3},
            'FloodMinNonLoadingThreads':{'before':2,'after':3},
            'DedicatedDecompressionMemoryBytes':{'before':1048576,'after':4194304}},
        'additionalMemoryPerDedicatedBufferBytes':3145728,
        'totalAdditionalMemoryMeasured':False,'nativeWorkerCountClampsPreserved':True,
        'gameplayContentRemoved':False,'graphicsQualityChanged':False,
        'streamingDistancesChanged':False,'aiPhysicsOrParticleTickChanged':False,
        'frameGenerationHDRControllerOptionsChanged':False,
        'configurationApplicationVerified':False,'stutterReductionVerified':False,
        'sustained30FPSVerified':False}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input',type=Path);parser.add_argument('output',type=Path)
    parser.add_argument('--reverse',action='store_true');args=parser.parse_args()
    source=args.input.resolve();destination=args.output.resolve()
    if source==destination or destination.exists():raise ValueError('Output must be a new file')
    patched,report=apply(source.read_bytes(),args.reverse)
    destination.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent,delete=False) as temporary:
        temporary.write(patched);temporary.flush();os.fsync(temporary.fileno());name=temporary.name
    try:
        Path(name).chmod(source.stat().st_mode & 0o777)
        # Atomic publication refuses a racing overwrite as well.
        os.link(name,destination)
    finally:Path(name).unlink(missing_ok=True)
    destination.with_suffix(destination.suffix+'.patch-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    print('New executable created. Its old code signature is invalid: re-sign it before packaging or use the supplied IPA. No installation performed.')

if __name__=='__main__':main()
