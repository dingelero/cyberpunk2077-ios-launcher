from common import ROOT,run
folder=ROOT/'work/performance/touch-v4-model';folder.mkdir(parents=True,exist_ok=True)
binary=folder/'check-touch-model'
run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-O2','-I',ROOT/'App/compat',ROOT/'tools/check_touch_model.m',ROOT/'App/compat/TouchLayout.m','-framework','Foundation','-framework','CoreGraphics','-o',binary])
print(run([binary,ROOT/'evidence/touch-v4-model-components.json']))
