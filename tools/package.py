import argparse,hashlib,json,os,stat,zipfile,plistlib
from pathlib import Path
from common import ROOT,output,write_json,sha,config,run
from macho import inspect,text_hash
from performance_profile import expected_text, VERSION
from mobile_engine_patch import VERSION as ENGINE_VERSION

def package(destination):
    app=output('ios')/'CyberpunkRebuilt.app'
    if not app.is_dir():raise ValueError('Build device app first')
    destination=Path(destination).resolve();destination.parent.mkdir(parents=True,exist_ok=True)
    run(['codesign','--verify','--strict',app])
    hashes={};platforms={};prefix='Payload/'+app.name+'/'
    with zipfile.ZipFile(destination,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6,allowZip64=True) as archive:
        for path in sorted(app.rglob('*')):
            if path.is_file():
                relative=path.relative_to(app).as_posix()
                archive.write(path,prefix+relative);hashes[prefix+relative]=sha(path)
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip():raise ValueError('IPA ZIP CRC failure')
        for name,expected in hashes.items():
            if hashlib.sha256(archive.read(name)).hexdigest()!=expected:raise ValueError('IPA byte verification failed: '+name)
        guest=archive.read(prefix+'Frameworks/CyberpunkGuest.dylib')
        info_plist=plistlib.loads(archive.read(prefix+'Info.plist'))
        if info_plist.get('UIDeviceFamily')!=[1,2]:raise ValueError('Both iPhone and iPad must be declared')
        files_sharing=info_plist.get('UIFileSharingEnabled') is True and info_plist.get('LSSupportsOpeningDocumentsInPlace') is True
        if not files_sharing:raise ValueError('Phone-only resource placement requires the app Documents folder to be exposed in Files')
        game_mode={'LSSupportsGameMode':info_plist.get('LSSupportsGameMode'),
                   'GCSupportsGameMode':info_plist.get('GCSupportsGameMode'),
                   'LSApplicationCategoryType':info_plist.get('LSApplicationCategoryType')}
        if game_mode!={'LSSupportsGameMode':True,'GCSupportsGameMode':True,'LSApplicationCategoryType':'public.app-category.games'}:
            raise ValueError('Packaged Game Mode declarations are missing')
        metadata=json.loads(archive.read(prefix+'guest.json'))
        logo=archive.read(prefix+'LauncherAssets/DingElero.png')
        logo_sha=hashlib.sha256(logo).hexdigest()
        if not logo.startswith(b'\x89PNG\r\n\x1a\n') or logo_sha!=sha(ROOT/'App/LauncherAssets/DingElero.png'):
            raise ValueError('Launcher logo missing or does not match the source asset')
        if b'CPLaunchGuide' not in archive.read(prefix+'CyberpunkRebuilt'):
            raise ValueError('Offline launcher tutorial is not linked into the host')
        expected=expected_text(metadata)
        if text_hash(guest)!=expected:raise ValueError('IPA guest instruction mismatch')
        if metadata.get('performanceProfile')==VERSION:
            if metadata.get('enginePatch')!=ENGINE_VERSION:raise ValueError('Game engine patch metadata missing')
            profile=json.loads(archive.read(prefix+'PerformanceProfile/profile.json'))
            if profile['version']!=VERSION or profile['nativeMetalFXIndex']!=1:raise ValueError('Performance profile mismatch')
            if profile.get('outputHeightChoices')!=[720,1080] or profile.get('interfaceLanguages')!=['zh','en'] or profile.get('devicePresetCount')!=6:
                raise ValueError('Universal options metadata missing')
            rendering=archive.read(prefix+'PerformanceProfile/rendering.ini')
            if hashlib.sha256(rendering).hexdigest()!=profile['profileRenderingSHA256']:raise ValueError('Packaged rendering configuration mismatch')
            from performance_profile import NODE_BATCH, RENDERING_SHA256
            suffix=b'\r\n[Streaming]\r\nMaxNodesPerFrame='+str(NODE_BATCH).encode()+b'\r\n'
            if not rendering.endswith(suffix) or hashlib.sha256(rendering[:-len(suffix)]).hexdigest()!=RENDERING_SHA256:
                raise ValueError('Unexpected changes outside the node attachment budget')
            if profile.get('graphicsQualityForced') is not False or profile.get('gameplayContentModified') is not False:raise ValueError('Feature-preserving profile declarations missing')
        for name in archive.namelist():
            if name.endswith('.dylib') or name==prefix+'CyberpunkRebuilt':
                info=inspect(archive.read(name))
                if info['platforms']!=[2]:raise ValueError('Packaged image is not an iOS device binary: '+name)
                if info['encrypted']:raise ValueError('Unexpected encrypted packaged image: '+name)
                platforms[name]=info['platforms']
                for dependency in info['dependencies']:
                    # The official iOS SDK intentionally exports IOKit with its
                    # versioned install name. This is not a desktop library.
                    native_iokit=dependency=='/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit'
                    if ('/Versions/' in dependency and not native_iokit) or 'AppKit.framework' in dependency or 'Cocoa.framework' in dependency:
                        raise ValueError('Unconverted desktop dependency: '+dependency)
    report={'ipa':destination.name,'size':destination.stat().st_size,'sha256':sha(destination),
            'zipCRCVerified':True,'allPackagedBytesVerified':True,'uuid':config()['game_uuid'],
            'patchedTextSHA256':expected,'performanceProfile':metadata.get('performanceProfile'),'enginePatch':metadata.get('enginePatch'),'fileCount':len(hashes),
            'resourcesBundled':False,'signing':'ad-hoc; requires user re-signing with embedded libraries',
            'appVersion':info_plist['CFBundleShortVersionString'],'appBuild':info_plist['CFBundleVersion'],
            'deviceFamilies':info_plist['UIDeviceFamily'],'outputHeightChoices':[720,1080],'interfaceLanguages':['zh','en'],'devicePresetCount':6,
            'allImagesNativeARM64IOS':True,'gameModeDeclarations':game_mode,
            'launcherBranding':{'credit':'DingElero','logoSHA256':logo_sha,'offlineTutorialLinked':True,'phoneOnlyFilePlacementGuideLinked':True},
            'filesAppDocumentsSharingEnabled':files_sharing,
            'gameModeEnabledOnDeviceVerified':False,'gameplayVerified':False,'platforms':platforms,'files':hashes}
    write_json(destination.with_suffix('.verification.json'),report)
    print(json.dumps({k:v for k,v in report.items() if k!='files'},ensure_ascii=False,indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('destination',type=Path);a=p.parse_args();package(a.destination)
