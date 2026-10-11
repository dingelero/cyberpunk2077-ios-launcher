from common import ROOT,run
folder=ROOT/'work/performance/universal-v5-model';folder.mkdir(parents=True,exist_ok=True)
binary=folder/'check-device-profiles'
run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-O2','-I',ROOT/'App',
    ROOT/'tools/check_device_profiles.m',ROOT/'App/LaunchPreferences.m',ROOT/'App/GamePacing.m',ROOT/'App/GameJSON.m',
    '-framework','Foundation','-framework','CoreGraphics','-o',binary])
print(run([binary,ROOT/'build/ios/CyberpunkRebuilt.app/PerformanceProfile/options.json',
    ROOT/'work/device-startup/20261011-streaming-v1-feedback/UserSettings.json',ROOT/'evidence/universal-v5-profile-components.json']))
