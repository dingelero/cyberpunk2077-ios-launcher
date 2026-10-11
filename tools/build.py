"""Build an unsigned/ad-hoc app that a normal sideload tool can re-sign."""
import argparse,json,plistlib,shutil,os
from pathlib import Path
from common import ROOT,config,run,output,write_json,sha
from build_compat import flags
from performance_profile import stage_configuration, VERSION, TEXT_SHA256
from macho import text_hash

def stage(platform):
    cfg=config();out=output(platform);app=out/'CyberpunkRebuilt.app';app.mkdir(parents=True,exist_ok=True)
    metadata=json.loads((out/'guest.json').read_text())
    if metadata.get('performanceProfile')!=VERSION or text_hash((out/'prepared/CyberpunkGuest.dylib').read_bytes())!=TEXT_SHA256:
        raise ValueError('Build requires the checked native-30 instruction profile; run performance_profile.py first')
    frameworks=app/'Frameworks';frameworks.mkdir(exist_ok=True)
    for directory in [out/'prepared',out/'compat']:
        for lib in directory.glob('*.dylib'):
            shutil.copy2(lib,frameworks/lib.name)
    if not (frameworks/'libCPCurl.dylib').exists(): raise ValueError('Native curl is not built')
    main,_,target=flags(platform)
    metalfx=['-framework','MetalFX'] if platform=='ios' else []
    run(main+['-I',ROOT/'App',ROOT/'App/main.m',ROOT/'App/LaunchMenu.m',ROOT/'App/LaunchGuide.m',ROOT/'App/LaunchPreferences.m',ROOT/'App/HostDiagnostics.m',ROOT/'App/DisplayPolicy.m',ROOT/'App/PerformanceProfile.m',ROOT/'App/GameJSON.m',ROOT/'App/GamePacing.m',ROOT/'App/GameEngineAudit.m','-o',app/'CyberpunkRebuilt',
              '-Wl,-rpath,@executable_path/Frameworks','-framework','UIKit','-framework','Foundation',
              '-framework','Metal','-framework','QuartzCore','-framework','GameController','-framework','AVFAudio']+metalfx,
        logfile=out/'logs/host-build.log')
    info=plistlib.loads((ROOT/'App/Info.plist').read_bytes())
    info.update({'CFBundleExecutable':'CyberpunkRebuilt','CFBundleIdentifier':cfg['bundle_id'],
       'CFBundleName':'CyberpunkRebuilt','CFBundleDisplayName':cfg['display_name'],
       'MinimumOSVersion':cfg['minimum_ios'],'CFBundleSupportedPlatforms':['iPhoneOS' if platform=='ios' else 'iPhoneSimulator']})
    original=Path(cfg['game_root'])/'Cyberpunk2077.app/Contents'
    icon_tool=out/'make-icon'
    run(['xcrun','--sdk','macosx','swiftc',ROOT/'tools/make_icon.swift','-o',icon_tool])
    run([icon_tool,original/'Resources/AppIcon.icns',app])
    info['CFBundleIcons']={'CFBundlePrimaryIcon':{'CFBundleIconFiles':['AppIcon60x60']}}
    info['CFBundleIcons~ipad']={'CFBundlePrimaryIcon':{'CFBundleIconFiles':['AppIcon60x60','AppIcon76x76','AppIcon83.5x83.5']}}
    (app/'Info.plist').write_bytes(plistlib.dumps(info))
    (app/'PkgInfo').write_bytes(b'APPL????')
    shutil.copytree(ROOT/'App/LauncherAssets',app/'LauncherAssets',dirs_exist_ok=True)
    shutil.copy2(out/'guest.json',app/'guest.json')
    stage_configuration(app)
    for license in ROOT.glob('*LICENSE*.txt'): shutil.copy2(license,app/license.name)
    for name in ['THIRD_PARTY_NOTICES.txt','curl-COPYING.txt','openssl-LICENSE.txt']:
        if (ROOT/name).exists():shutil.copy2(ROOT/name,app/name)
    # Small, legitimate metadata is bundled. Large game archives remain external.
    content=app/'GameData/Cyberpunk2077.app/Contents';content.mkdir(parents=True,exist_ok=True)
    shutil.copy2(original/'Info.plist',content/'Info.plist')
    shutil.copytree(original/'Resources',content/'Resources',dirs_exist_ok=True)
    for lib in frameworks.glob('*.dylib'):
        run(['codesign','--force','--sign','-',lib])
        run(['codesign','--verify','--strict',lib])
        run(['xcrun','dyld_info','-validate_only',lib])
    signature=['codesign','--force','--sign','-']
    if platform=='ios': signature+=['--entitlements',ROOT/'App/Entitlements.plist']
    run(signature+[app])
    run(['codesign','--verify','--strict',app])
    write_json(out/'app-build.json',{'platform':platform,'target':target,'app':str(app),
        'adHocSignedForResigning':True,'developmentSigned':False,'resourcesBundled':False,
        'gameplayVerified':False,'binaries':{p.name:sha(p) for p in frameworks.glob('*.dylib')}})
    print(app)
    return app

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--platform',choices=['ios','iossim'],default='ios');a=p.parse_args();stage(a.platform)
