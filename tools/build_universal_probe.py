"""Build production launcher and touch UI in a game-free Simulator harness."""
import plistlib,shutil
from common import ROOT,output,run
from build_compat import flags
from performance_profile import stage_configuration
app=ROOT/'work/performance/UniversalUIProbe.app';app.mkdir(parents=True,exist_ok=True)
frameworks=app/'Frameworks';frameworks.mkdir(exist_ok=True)
shutil.copy2(output('iossim')/'compat/libCPCompat.dylib',frameworks/'libCPCompat.dylib')
base,_,_=flags('iossim')
run(base+['-I',ROOT/'App',ROOT/'App/probes/UniversalUIProbe.m',ROOT/'App/LaunchMenu.m',ROOT/'App/LaunchGuide.m',ROOT/'App/LaunchPreferences.m',
    ROOT/'App/DisplayPolicy.m',ROOT/'App/PerformanceProfile.m',ROOT/'App/GamePacing.m',ROOT/'App/GameJSON.m',
    '-L',frameworks,'-Wl,-rpath,@executable_path/Frameworks',
    '-framework','UIKit','-framework','Foundation','-framework','Metal','-framework','CoreGraphics','-framework','GameController','-framework','QuartzCore','-lCPCompat',
    '-o',app/'UniversalUIProbe'])
info=plistlib.loads((ROOT/'App/Info.plist').read_bytes())
info.update({'CFBundleExecutable':'UniversalUIProbe','CFBundleIdentifier':'local.cyberpunk.universal-ui-probe',
    'CFBundleDisplayName':'Universal UI Probe','CFBundleSupportedPlatforms':['iPhoneSimulator']})
info['UIApplicationSceneManifest']['UISceneConfigurations']['UIWindowSceneSessionRoleApplication'][0]['UISceneDelegateClassName']='CPProbeScene'
(app/'Info.plist').write_bytes(plistlib.dumps(info));stage_configuration(app)
shutil.copytree(ROOT/'App/LauncherAssets',app/'LauncherAssets',dirs_exist_ok=True)
run(['codesign','--force','--sign','-',frameworks/'libCPCompat.dylib']);run(['codesign','--force','--sign','-',app]);print(app)
