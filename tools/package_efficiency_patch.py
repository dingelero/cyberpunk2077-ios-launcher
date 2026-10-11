#!/usr/bin/env python3
"""Create a small reversible IPA delta, excluding full commercial executables."""
import argparse,difflib,hashlib,json,shutil,stat,zipfile,plistlib
from pathlib import Path
from common import ROOT,sha,write_json
from apply_efficiency_patch import sha_bytes,safe_name

COMMERCIAL={'CyberpunkGuest.dylib','libBink2MacArm64.dylib','libGameServicesSteam.dylib','libREDGalaxy64.dylib','libsteam_api.dylib'}
def delta(before,after):
    spans=[]
    for start in range(0,len(after),65536):
        left=before[start:start+65536];right=after[start:start+65536]
        if left==right:continue
        i=0
        while i<len(right):
            if i<len(left) and left[i]==right[i]:i+=1;continue
            first=i;last=i+1;i+=1
            while i<len(right):
                if i>=len(left) or left[i]!=right[i]:last=i+1
                if i-last>=16:break
                i+=1
            spans.append({'offset':start+first,'hex':right[first:last].hex()})
    return {'size':len(after),'ranges':spans}
def package(bases,target,destination,handoff=None,snapshot=None,include_engine_source=False):
    destination=Path(destination).resolve();folder=destination.with_suffix('')
    if folder.exists():raise FileExistsError('Choose a new output name; patch working folder already exists: '+str(folder))
    folder.mkdir(parents=True);payload=folder/'payload';payload.mkdir()
    shutil.copy2(ROOT/'tools/apply_efficiency_patch.py',folder/'apply_efficiency_patch.py')
    manifest={'format':'cp2077-ipa-delta-v1','targetDevice':'iPhone 16 Pro Max','sustained30FPSVerified':False,
        'gameplayContentRemoved':False,'nativeARM64Metal':True,'usesJIT':False,'usesCPUEmulation':False,'usesStreaming':False,
        'fullCommercialExecutablesIncluded':False,'target':{'referenceIPA':Path(target).name,
        'referenceIPASHA256':sha(target),'files':{}},'bases':[]}
    stored={}
    def store(data,suffix):
        digest=sha_bytes(data);name='payload/'+digest+suffix
        if name not in stored:(folder/name).write_bytes(data);stored[name]=digest
        return {'payload':name,'payloadSHA256':digest}
    with zipfile.ZipFile(target) as final:
        if final.testzip():raise ValueError('Target IPA ZIP failure')
        prefix='Payload/CyberpunkRebuilt.app/'
        info=plistlib.loads(final.read(prefix+'Info.plist'))
        manifest['target']['version']=info['CFBundleShortVersionString']+'/build'+info['CFBundleVersion']
        guest=json.loads(final.read(prefix+'guest.json'))
        if guest.get('performanceProfile')=='universal-v5':manifest['targetDevice']='iPhone and iPad; six selectable device presets'
        if guest.get('enginePatch'):manifest['enginePatch']=guest['enginePatch']
        for name in final.namelist():
            safe_name(name);info=final.getinfo(name);data=final.read(name)
            manifest['target']['files'][name]={'sha256':sha_bytes(data),'size':len(data),'zip':{
                key:getattr(info,key) for key in ('date_time','create_system','create_version','extract_version','external_attr','internal_attr')}}
        for base in bases:
            variant={'name':Path(base).name,'sha256':sha(base),'entries':{}}
            with zipfile.ZipFile(base) as original:
                if original.testzip():raise ValueError('Base IPA ZIP failure')
                for name in final.namelist():
                    exists=name in original.namelist();before=original.read(name) if exists else b'';after=final.read(name)
                    entry={'sourceExists':exists,'sourceSHA256':sha_bytes(before)}
                    if before==after:entry['operation']='copy'
                    elif Path(name).name in COMMERCIAL:
                        if not exists:raise ValueError('Patch cannot include a full commercial executable')
                        changes=json.dumps(delta(before,after),separators=(',',':')).encode()
                        if len(changes)>2*1024*1024:raise ValueError('Commercial executable delta unexpectedly large')
                        entry.update({'operation':'ranges',**store(changes,'.json')})
                    else:entry.update({'operation':'replace',**store(after,'.bin')})
                    variant['entries'][name]=entry
            manifest['bases'].append(variant)
    write_json(folder/'manifest.json',manifest)
    snapshot=Path(snapshot) if snapshot else ROOT/'work/performance/v4-baseline';diff=[]
    for section in ('App','tools'):
        for path in sorted((ROOT/section).rglob('*')):
            if not path.is_file() or path.suffix not in {'.h','.m','.py','.plist'} or '__pycache__' in path.parts:continue
            relative=path.relative_to(ROOT);old=snapshot/relative
            before=old.read_text().splitlines(keepends=True) if old.exists() else []
            after=path.read_text().splitlines(keepends=True)
            diff.extend(difflib.unified_diff(before,after,fromfile='a/'+relative.as_posix(),tofile='b/'+relative.as_posix()))
    (folder/'source-changes.diff').write_text(''.join(diff))
    command=folder/'生成优化版IPA.command'
    command.write_text('''#!/bin/zsh
cd -- "${0:A:h}" || exit 1
python3 ./apply_efficiency_patch.py
task_patch_status=$?
print "补丁生成结束，退出码：$task_patch_status。不会自动签名或安装。"
read "task_patch_key?按回车关闭。"
exit $task_patch_status
''');command.chmod(0o755)
    if include_engine_source:
        from mobile_engine_patch import VERSION, ADDRESS, OLD, NEW, BASE_TEXT, TEXT_SHA256
        from game_streaming_patch import UUID
        engine=folder/'engine-tools';engine.mkdir()
        for name in ('mobile_engine_patch.py','game_streaming_patch.py','macho.py'):shutil.copy2(ROOT/'tools'/name,engine/name)
        write_json(engine/'recipe.json',{'version':VERSION,'uuid':UUID,'textHashPairs':{BASE_TEXT:TEXT_SHA256},
            'instructions':[{'virtualAddress':hex(ADDRESS),'before':hex(OLD),'after':hex(NEW)}],
            'failedV1StreamingDefaultsReverted':True,
            'commercialGameCodeIncluded':False,'sustained30FPSVerified':False})
    readme=Path(handoff) if handoff else ROOT/'evidence/performance-v4-handoff.md'
    if not readme.exists():raise ValueError('Create the patch handoff instructions first')
    shutil.copy2(readme,folder/'使用说明.md')
    with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for path in sorted(folder.rglob('*')):
            if path.is_file():archive.write(path,folder.name+'/'+path.relative_to(folder).as_posix())
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip():raise ValueError('Patch ZIP CRC failure')
        for path in folder.rglob('*'):
            if path.is_file() and sha_bytes(archive.read(folder.name+'/'+path.relative_to(folder).as_posix()))!=sha(path):raise ValueError('Patch ZIP byte mismatch')
    report={'archive':destination.name,'size':destination.stat().st_size,'sha256':sha(destination),
        'payloadFiles':len(stored),'baseVariants':len(bases),'crcAndBytesVerified':True,'fullCommercialExecutablesIncluded':False,
        'userMustResign':True,'sustained30FPSVerified':False}
    write_json(destination.with_suffix('.verification.json'),report);print(json.dumps(report,indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--base',type=Path,action='append',required=True)
    p.add_argument('--target',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--handoff',type=Path);p.add_argument('--snapshot',type=Path);p.add_argument('--include-engine-source',action='store_true')
    a=p.parse_args();package(a.base,a.target,a.output,a.handoff,a.snapshot,a.include_engine_source)
