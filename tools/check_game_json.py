#!/usr/bin/env python3
"""Check native serialization against the game's typed numeric JSON fields."""
import argparse,json
from pathlib import Path
from common import ROOT,config,run,write_json

FIELDS={'value','default_value','min_value','max_value','step_value'}
def float_fields(obj,path=()):
    result=[]
    if isinstance(obj,dict):
        if obj.get('type')=='float':
            result.extend((path+(k,),obj[k]) for k in FIELDS&obj.keys())
        for k,v in obj.items():result.extend(float_fields(v,path+(k,)))
    elif isinstance(obj,list):
        for i,v in enumerate(obj):result.extend(float_fields(v,path+(i,)))
    return result

def check(inputs,destination):
    destination=Path(destination);destination.mkdir(parents=True,exist_ok=True)
    binary=destination/'check-game-json'
    run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-O2','-I',ROOT/'App',
        ROOT/'tools/check_game_json.m',ROOT/'App/GameJSON.m','-framework','Foundation','-o',binary])
    reports=[]
    for i,source in enumerate(inputs):
        target=destination/f'fixed-{i}.json'
        run([binary,source,target])
        current=json.loads(target.read_text());previous=json.loads(Path(str(target)+'.previous').read_text())
        if current!=previous:raise ValueError('Native numeric values or other JSON content changed')
        fields=float_fields(current);bad=[p for p,v in fields if type(v) is not float]
        before=float_fields(previous);before_bad=[p for p,v in before if type(v) is not float]
        if not fields or bad or not before_bad:raise ValueError('Regression did not reproduce or fix the float token failure')
        reports.append({'input':Path(source).name,'floatFieldsChecked':len(fields),
            'previousIncorrectIntegerFields':len(before_bad),'fixedIncorrectFields':len(bad),
            'numericValuesAndOtherJSONUnchanged':True,'invalidFloatBooleanRejected':True})
    write_json(destination/'result.json',{'scope':'Native Foundation serializer regression; no game execution',
        'passed':True,'inputs':reports})
    print(json.dumps(reports,ensure_ascii=False,indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('inputs',nargs='*',type=Path)
    p.add_argument('--output',type=Path,default=ROOT/'work/game-json-check')
    a=p.parse_args();inputs=a.inputs or [Path(config()['game_root'])/'r6/config/settings/platform/mac/options.json']
    check(inputs,a.output)
