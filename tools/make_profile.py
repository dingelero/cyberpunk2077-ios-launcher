#!/usr/bin/env python3
"""Derive a reversible native 720p/30 target from this version's actual settings."""
import argparse,json
from pathlib import Path

def make(source,destination,hdr=False,preserve_quality=False):
    value=json.loads(source.read_text());changes=[]
    fixed={'Resolution':'1280x720','MaximumFPS_OnOff':True,'MaximumFPS_Value':30,
        'ResolutionScaling':'Off','FrameGeneration':'Off','FSR3_FrameGeneration':False,
        'DynamicResolutionScaling':False,'DRS_TargetFPS':30,'DRS_MinResolution':100,'DRS_MaxResolution':100,
        'TextureQuality':'Low','CrowdDensity':'Low','FieldOfView':80.0,
        'FilmGrain':False,'ChromaticAberration':False,'DepthOfField':False,'MotionBlur':'Off',
        'HDRModes':'HDR10_PQ' if hdr else 'None', 'MaxMonitorBrightness':1000.0,'PaperWhiteLevel':200.0,
        'TonemappingMidpoint':2.0,'HDR10PlusGaming':False,'Anisotropy':4}
    if preserve_quality:
        keep={'Resolution','MaximumFPS_OnOff','MaximumFPS_Value','ResolutionScaling','FrameGeneration',
            'FSR3_FrameGeneration','DynamicResolutionScaling','HDRModes','MaxMonitorBrightness','PaperWhiteLevel','TonemappingMidpoint'}
        fixed={k:v for k,v in fixed.items() if k in keep}
    for group in value['data']:
        path=group['group_name']
        for option in group['options']:
            name=option['name'];new=option['value']
            if not preserve_quality:
                if path=='/graphics/raytracing':new=False if option['type']=='bool' else 'Off'
                elif path=='/graphics/advanced' and option.get('values'):new=option['values'][0]
                elif path=='/graphics/advanced' and option['type']=='bool':new=False
            if name in fixed:new=fixed[name]
            if new==option['value']:continue
            choices=option.get('values')
            if choices is not None and new not in choices:raise ValueError('Unsupported enum '+name+': '+str(new))
            if 'min_value' in option and not option['min_value']<=new<=option['max_value']:raise ValueError('Out of range '+name)
            changes.append({'group':path,'name':name,'before':option['value'],'after':new})
            option['value']=new
            if choices:option['index']=choices.index(new)
            elif name=='Resolution':option['index']=1 # Native mode, app 720p, app 1080p.
            elif name=='HDRModes':option['index']=1 if hdr else 0
            elif name=='FrameGeneration':option['index']=0
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text(json.dumps(value,ensure_ascii=False,indent=4)+'\n')
    destination.with_suffix('.changes.json').write_text(json.dumps({'target':'1280x720 output; no upscaling or frame generation; 30 FPS cap',
        'hdrRequested':hdr,'performanceVerified':False,'changes':changes},ensure_ascii=False,indent=2)+'\n')
    print('Created',destination,'with',len(changes),'changes; physical-device verification still required.')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('destination',type=Path)
    p.add_argument('--hdr',action='store_true');p.add_argument('--preserve-quality',action='store_true')
    a=p.parse_args();make(a.source,a.destination,a.hdr,a.preserve_quality)
