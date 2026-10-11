#!/usr/bin/env python3
"""Create an inspected source handoff without original game files or build products."""
import argparse,hashlib,json,zipfile,re,tempfile
from pathlib import Path
from common import ROOT,sha,write_json

def sanitize(data):
    try:text=data.decode('utf-8')
    except UnicodeDecodeError:raise ValueError('Source handoff only accepts text files')
    # Logs and JSON may contain slash-escaped absolute container paths.
    for old,new in [(str(ROOT),'<project>'),(str(Path.home()),'~'),
                    ('<simulator-device>','<simulator-device>'),
                    ('<paired-device>','<paired-device>'),
                    ('<paired-device>','<paired-device>')]:
        text=text.replace(old,new).replace(old.replace('/','\\/'),new.replace('/','\\/'))
    return text.encode('utf-8')

def package(destination):
    candidates=[]
    for folder,extensions in [('App',{'.m','.h','.plist','.inc','.LICENSE'}),
                              ('tools',{'.py','.m','.swift','.txt','.command'}),
                              ('evidence',{'.json','.md','.txt','.log','.stderr','.stdout'})]:
        for path in sorted((ROOT/folder).rglob('*')):
            if path.is_file() and path.suffix in extensions and '__pycache__' not in path.parts:
                candidates.append(path)
    for name in ['README.md','config.example.json','LICENSE-Stray-iOS.txt','THIRD_PARTY_NOTICES.txt',
                 'curl-COPYING.txt','openssl-LICENSE.txt']:
        path=ROOT/name
        if not path.is_file():raise ValueError('Required source handoff file missing: '+name)
        candidates.append(path)
    # The user supplied this launcher logo. It is the sole binary source asset;
    # commercial game artwork and other binary/build files remain excluded.
    logo=ROOT/'App/LauncherAssets/DingElero.png'
    if not logo.is_file() or not logo.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('DingElero launcher logo is missing or invalid')
    candidates.append(logo)
    destination=Path(destination).resolve();destination.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=destination.name+'.',suffix='.building',dir=destination.parent,delete=False) as file:
        staged=Path(file.name)
    contents={}
    with zipfile.ZipFile(staged,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for path in candidates:
            name='cp2077-port/'+path.relative_to(ROOT).as_posix()
            data=path.read_bytes() if path==logo else sanitize(path.read_bytes())
            if path!=logo and re.search(rb'\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b',data):raise ValueError('Device identity leaked: '+name)
            archive.writestr(name,data)
            contents[name]=hashlib.sha256(data).hexdigest()
    with zipfile.ZipFile(staged) as archive:
        if archive.testzip():raise ValueError('Source ZIP CRC failure')
        for name,expected in contents.items():
            if hashlib.sha256(archive.read(name)).hexdigest()!=expected:raise ValueError('Source ZIP byte mismatch')
        if any(x.endswith(('.dylib','.ipa','.p12','.mobileprovision','.archive','.metallib','.icns','.car')) for x in archive.namelist()):
            raise ValueError('Source ZIP includes game/build/signing data')
    # Import helpers may open the existing ZIP during an update. Publish only
    # a fully closed, inspected archive through an atomic same-volume rename.
    staged.replace(destination)
    report={'archive':destination.name,'sha256':sha(destination),'size':destination.stat().st_size,
            'fileCount':len(contents),'crcAndSHA256Verified':True,'originalGameFilesIncluded':False,
            'buildProductsIncluded':False,'signingMaterialIncluded':False,'evidencePathsRedacted':True,'userSuppliedLauncherLogoIncluded':True,'files':contents}
    write_json(destination.with_suffix('.verification.json'),report)
    print(json.dumps({k:v for k,v in report.items() if k!='files'},ensure_ascii=False,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('destination',type=Path);args=parser.parse_args();package(args.destination)
