import plistlib
from common import ROOT,run
from build_compat import flags
app=ROOT/'work/performance/TouchBackendProbe.app';app.mkdir(parents=True,exist_ok=True)
base,_,_=flags('iossim');base[base.index('-target')+1]='arm64-apple-ios26.0-simulator'
run(base+[ROOT/'App/probes/TouchBackendProbe.m','-framework','UIKit','-framework','TouchController','-framework','GameController','-framework','Metal','-framework','Foundation','-o',app/'TouchBackendProbe'])
info={'CFBundleIdentifier':'local.cyberpunk.touch-backend-probe','CFBundleExecutable':'TouchBackendProbe','CFBundleName':'TouchBackendProbe','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','MinimumOSVersion':'26.0','CFBundleSupportedPlatforms':['iPhoneSimulator'],'UIDeviceFamily':[1,2],'UILaunchScreen':{},'UIApplicationSceneManifest':{'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Backend','UISceneDelegateClassName':'CPBackendScene'}]}}}
(app/'Info.plist').write_bytes(plistlib.dumps(info));run(['codesign','--force','--sign','-',app]);print(app)
