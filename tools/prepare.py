import argparse,json
from pathlib import Path
from common import ROOT,config,run,sha,output,write_json
from audit import audit,thin
from macho import convert,text_hash

COMPAT={'AppKit','Cocoa','Foundation','CoreGraphics','CoreAudio','AudioToolbox','AudioUnit','Carbon','IOKit','Metal','Security'}
LIBNAMES={'libGameServicesSteam.dylib','libsteam_api.dylib','libBink2MacArm64.dylib','libREDGalaxy64.dylib'}

def remap(path):
    name=path.rsplit('/',1)[-1]
    if name in LIBNAMES: return '@rpath/'+name
    if name in COMPAT: return '@rpath/libCP'+name+'.dylib'
    if name.startswith('libSystem.'): return '@rpath/libCPSystem.dylib'
    if name.startswith('libcurl.'): return '@rpath/libCPCurl.dylib'
    if '/Versions/' in path:
        return path.split('/Versions/')[0]+'/'+name
    return path

def prepare(platform):
    cfg=config();out=output(platform)/'prepared';out.mkdir(parents=True,exist_ok=True)
    records=audit();converted=[]
    for record in records:
        name=record['name'];source=Path(record['path'])
        data=thin(source,out/(name+'.thin'))
        weak_unused=[]
        if platform=='iossim' and name=='CyberpunkGuest.dylib':
            imports=run(['xcrun','dyld_info','-imports',source])
            # MetalFX is absent from the simulator runtime. This exact game
            # version imports no symbols from it; keep its ordinal but weaken
            # its load for diagnostics only. The device still requires native
            # MetalFX, and simulator results cannot establish game rendering.
            if '(from MetalFX)' in imports: raise ValueError('Simulator cannot validate imported MetalFX APIs')
            weak_unused=['MetalFX']
        new,details=convert(data,name,platform,cfg['minimum_ios'],cfg['sdk_version'],remap,main=name=='CyberpunkGuest.dylib',weak_unused=weak_unused)
        target=out/name;target.write_bytes(new);target.chmod(0o755)
        validation=run(['xcrun','dyld_info','-validate_only',target])
        converted.append({'name':name,'sourceSHA256':record['sha256'],'convertedSHA256':sha(target),**details})
    write_json(output(platform)/'conversion.json',{'platform':platform,'images':converted})
    guest=records[0]
    write_json(output(platform)/'guest.json',{'uuid':cfg['game_uuid'],'entryOffset':guest['entryOffset'],
          'libraries':[r['name'] for r in records if r['name']!='CyberpunkGuest.dylib'],
          'resourcesBundled':False,'minimumIOS':cfg['minimum_ios'],
          'files':[{'path':'archive/Mac/content/basegame_2_mainmenu.archive','size':327680,'required':True},
                   {'path':'r6/cache/tweakdb.bin','required':True}],
          'gameplayVerified':False,'noJIT':True,'noCPUEmulation':True,'noStreaming':True})
    print(f'Prepared {len(converted)} {platform} images, CPU instructions preserved.')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--platform',choices=['ios','iossim'],default='ios');a=p.parse_args();prepare(a.platform)
