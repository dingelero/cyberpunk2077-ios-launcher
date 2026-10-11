"""Compile native compatibility libraries for the explicit device/simulator platform."""
import argparse,json
from pathlib import Path
from common import ROOT,config,run,output,write_json,sha

FRAMEWORKS=['Foundation','UIKit','QuartzCore','Metal','CoreGraphics','GameController',
            'AudioToolbox','CoreAudio','AVFAudio','IOKit','ImageIO','Security','CoreFoundation']
FACADES=['AppKit','Cocoa','Foundation','CoreGraphics','CoreAudio','AudioToolbox','AudioUnit','Carbon','IOKit','Metal','System','Security']
SYSTEM={'Open':'open','Fopen':'fopen','Freopen':'freopen','Stat':'stat','Access':'access',
        'Opendir':'opendir','Chdir':'chdir','Mkdir':'mkdir','Unlink':'unlink','Rmdir':'rmdir',
        'Rename':'rename','Dlopen':'dlopen','GetExecutablePath':'_NSGetExecutablePath','Mmap':'mmap'}
AUDIO={'AudioObjectGetPropertyDataSize':'AudioObjectGetPropertyDataSize',
       'AudioObjectGetPropertyData':'AudioObjectGetPropertyData',
       'AudioObjectSetPropertyData':'AudioObjectSetPropertyData',
       'AUGraphAddNode':'AUGraphAddNode','AUGraphSetNodeInputCallback':'AUGraphSetNodeInputCallback',
       'AUGraphStart':'AUGraphStart','AUGraphStop':'AUGraphStop','DisposeAUGraph':'DisposeAUGraph',
       'AudioOutputUnitStart':'AudioOutputUnitStart','AudioOutputUnitStop':'AudioOutputUnitStop'}

def flags(platform):
    sdk='iphoneos' if platform=='ios' else 'iphonesimulator'
    suffix='' if platform=='ios' else '-simulator'
    target='arm64-apple-ios'+config()['minimum_ios']+suffix
    root=run(['xcrun','--sdk',sdk,'--show-sdk-path']).strip()
    return ['xcrun','--sdk',sdk,'clang','-target',target,'-isysroot',root,'-g','-O2',
            '-Wno-deprecated-declarations','-fobjc-arc','-fmodules'],root,target

def build(platform):
    directory=output(platform)/'compat';directory.mkdir(parents=True,exist_ok=True)
    base,sdk,target=flags(platform)
    lib=directory/'libCPCompat.dylib'
    sources=sorted((ROOT/'App/compat').glob('*.m'))
    args=base+['-dynamiclib','-I',ROOT/'App','-I',ROOT/'App/compat']+sources
    args+=['-o',lib,'-Wl,-install_name,@rpath/libCPCompat.dylib','-Wl,-rpath,@loader_path']
    for framework in FRAMEWORKS: args+=['-Wl,-reexport_framework,'+framework]
    args+=['-Wl,-reexport_library,'+sdk+'/usr/lib/libSystem.tbd']
    for cp,native in SYSTEM.items(): args+=['-Wl,-alias,_CPGuest'+cp+',_'+native]
    for cp,native in AUDIO.items(): args+=['-Wl,-alias,_CP'+cp+',_'+native]
    # NSBundle is a macOS facade only for guest-linked Foundation; UIKit continues
    # binding the system class via its own native Foundation dependency ordinal.
    for cp,native in [('CPGameBundle','NSBundle'),('CP2077Font','NSFont'),('CP2077Color','NSColor')]:
        for prefix in ['CLASS','METACLASS']:
            args+=['-Wl,-alias,_OBJC_'+prefix+'_$_'+cp+',_OBJC_'+prefix+'_$_'+native]
    run(args,logfile=output(platform)/'logs/compat-build.log')
    run(['xcrun','dyld_info','-validate_only',lib])
    dummy=directory/'facade.c';dummy.write_text('void CPFacadeAnchor(void) {}\n')
    for facade in FACADES:
        path=directory/('libCP'+facade+'.dylib')
        run(base+['-dynamiclib',dummy,'-o',path,'-Wl,-install_name,@rpath/'+path.name,
                  '-Wl,-reexport_library,'+str(lib),'-Wl,-rpath,@loader_path'],
            logfile=output(platform)/('logs/facade-'+facade+'.log'))
        run(['xcrun','dyld_info','-validate_only',path])
    write_json(output(platform)/'compat-build.json',{'platform':platform,'target':target,'sdk':sdk,
       'sources':[p.name for p in sources],'libraries':{p.name:sha(p) for p in directory.glob('*.dylib')},
       'runtimeVerified':False})
    print('Built native compatibility library and '+str(len(FACADES))+' dependency facades for '+platform)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--platform',choices=['ios','iossim'],default='ios');a=p.parse_args();build(a.platform)
