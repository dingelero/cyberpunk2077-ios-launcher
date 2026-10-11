"""Build a separate UIKit touch probe for Simulator, without guest binaries."""
import plistlib,shutil
from common import ROOT,run,output
from build_compat import flags
app=ROOT/'work/performance/MobileControlsProbe.app';app.mkdir(parents=True,exist_ok=True)
frameworks=app/'Frameworks';frameworks.mkdir(exist_ok=True)
shutil.copy2(output('iossim')/'compat/libCPCompat.dylib',frameworks/'libCPCompat.dylib')
base,_,_=flags('iossim')
run(base+['-I',ROOT/'App',ROOT/'App/probes/MobileControlsProbe.m','-L',frameworks,'-lCPCompat',
    '-Wl,-rpath,@executable_path/Frameworks','-framework','UIKit','-framework','GameController','-framework','Foundation',
    '-o',app/'MobileControlsProbe'])
info={'CFBundleIdentifier':'local.cyberpunk.mobile-controls-probe','CFBundleExecutable':'MobileControlsProbe',
    'CFBundleName':'MobileControlsProbe','CFBundleDisplayName':'触摸组件验证','CFBundlePackageType':'APPL',
    'CFBundleShortVersionString':'1.0','CFBundleVersion':'1','MinimumOSVersion':'18.0','CFBundleSupportedPlatforms':['iPhoneSimulator'],
    'UISupportedInterfaceOrientations':['UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],
    'UIDeviceFamily':[1,2],'UIRequiresFullScreen':True,'UILaunchScreen':{},
    'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{
        'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'TouchProbe','UISceneDelegateClassName':'CPProbeScene'}]}}}
(app/'Info.plist').write_bytes(plistlib.dumps(info))
run(['codesign','--force','--sign','-',frameworks/'libCPCompat.dylib']);run(['codesign','--force','--sign','-',app]);print(app)
