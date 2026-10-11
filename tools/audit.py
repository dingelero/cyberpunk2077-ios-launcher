import argparse, json, tempfile
from pathlib import Path
from common import ROOT,config,run,sha,write_json
from macho import inspect

FILES={
 'CyberpunkGuest.dylib':('Contents/MacOS/Cyberpunk2077','2a6ba5c2847759f7ed896b6bed7b36fe5a7990f75fe9f779383a62adb19d5a15'),
 'libBink2MacArm64.dylib':('Contents/Frameworks/libBink2MacArm64.dylib','fdc4b9cf72ae6b6c70b22361e33712a76f750c7e4231be238cae0cecf279c9cf'),
 'libGameServicesSteam.dylib':('Contents/Frameworks/libGameServicesSteam.dylib','56b89d01e9e3138fcb6036de7886e33bf758e22e834b1a2948a28c3f35ac4f5d'),
 'libREDGalaxy64.dylib':('Contents/Frameworks/libREDGalaxy64.dylib','5f565f36d1979de843885fff90901e01e4a5de77dbaf62327e3113c7d8685ea2'),
 'libsteam_api.dylib':('Contents/Frameworks/libsteam_api.dylib','46d00ce19e951c1b6e95d8df4b63625ec3a03f927664fb993a7fa0396fd6b200'),
}

def thin(path, destination):
    data=path.read_bytes()
    if data[:4]==b'\xcf\xfa\xed\xfe': return data
    run(['xcrun','lipo',path,'-thin','arm64','-output',destination])
    return destination.read_bytes()

def audit():
    cfg=config();app=Path(cfg['game_root'])/'Cyberpunk2077.app';records=[]
    with tempfile.TemporaryDirectory() as temp:
        for name,(relative,expected) in FILES.items():
            path=app/relative;digest=sha(path)
            if digest!=expected: raise ValueError('Unsupported input version: '+str(path))
            data=thin(path,Path(temp)/name);info=inspect(data)
            if info['encrypted']: raise ValueError('Encrypted game image unsupported')
            if name=='CyberpunkGuest.dylib' and info['uuid']!=cfg['game_uuid']:
                raise ValueError('Unsupported main UUID')
            imports=run(['xcrun','nm','-u',Path(temp)/name if path.read_bytes()[:4]!=b'\xcf\xfa\xed\xfe' else path]).splitlines()
            records.append({'name':name,'path':str(path),'sha256':digest,'imports':imports,**info})
    write_json(ROOT/'evidence/input-audit.json',{'versionLocked':True,'originalsReadOnly':True,'images':records})
    return records

if __name__=='__main__':
    result=audit();print(json.dumps([{'name':r['name'],'uuid':r['uuid'],'imports':len(r['imports'])} for r in result],indent=2))
