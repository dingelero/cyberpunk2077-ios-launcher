#!/usr/bin/env python3
"""Back up and import this game's saves/settings through its paired USB container."""
import argparse, asyncio, hashlib, json, posixpath
from pathlib import Path
from datetime import datetime

REMOTE='/Library/Application Support/CD Projekt Red/Cyberpunk 2077'
BUFFER=1024*1024

async def read(afc, path):
    size=int((await afc.stat(path))['st_size'])
    if size>64*1024*1024:raise ValueError('Unexpectedly large user-data file: '+path)
    handle=await afc.fopen(path,'r');chunks=[]
    try:
        remaining=size
        while remaining:
            data=await afc.fread(handle,min(BUFFER,remaining))
            if not data:raise IOError('Short read: '+path)
            chunks.append(data);remaining-=len(data)
    finally:await afc.fclose(handle)
    return b''.join(chunks)

async def files(afc, root):
    from pymobiledevice3.exceptions import AfcFileNotFoundError
    try:entries=await afc.listdir(root)
    except AfcFileNotFoundError:return []
    result=[]
    for name in sorted(entries):
        if name in ('.','..'):continue
        path=posixpath.join(root,name);kind=(await afc.stat(path)).get('st_ifmt')
        if kind=='S_IFDIR':result.extend(await files(afc,path))
        elif kind=='S_IFREG':result.append(path)
        else:raise ValueError('Unsupported user-data entry: '+path)
    return result

async def write_verified(afc, path, data):
    await afc.makedirs(posixpath.dirname(path))
    part=path+'.cp-import-part';handle=await afc.fopen(part,'w')
    try:
        for offset in range(0,len(data),BUFFER):await afc.fwrite(handle,data[offset:offset+BUFFER],chunk_size=BUFFER)
    finally:await afc.fclose(handle)
    digest=hashlib.sha256(data).hexdigest()
    if hashlib.sha256(await read(afc,part)).hexdigest()!=digest:raise IOError('Device hash mismatch: '+path)
    await afc.rename(part,path)
    if hashlib.sha256(await read(afc,path)).hexdigest()!=digest:raise IOError('Final hash mismatch: '+path)
    return {'path':path.removeprefix(REMOTE+'/'),'bytes':len(data),'sha256':digest,'deviceVerified':True}

async def main(args):
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.services.house_arrest import HouseArrestService
    backup=args.backup.resolve();backup.mkdir(parents=True,exist_ok=True)
    report={'scope':'Game saves and UserSettings only; original Mac files unchanged','backup':str(backup),'backedUp':[],
            'imported':[],'gameLoadVerified':False,'newGameSaveVerified':False}
    lockdown=await create_using_usbmux(serial=args.device,connection_type='USB',autopair=False,
        pairing_records_cache_folder=Path(__file__).resolve().parents[1]/'work/pairing-cache')
    async with lockdown:
        async with await HouseArrestService.create(lockdown,args.bundle_id,documents_only=False) as afc:
            existing=await files(afc,REMOTE)
            backup_files=[p for p in existing if p==REMOTE+'/UserSettings.json'] if args.profile and not args.saves else existing
            for remote in backup_files:
                relative=remote.removeprefix(REMOTE+'/');data=await read(afc,remote)
                local=backup/'before'/relative;local.parent.mkdir(parents=True,exist_ok=True);local.write_bytes(data)
                if hashlib.sha256(local.read_bytes()).hexdigest()!=hashlib.sha256(data).hexdigest():raise IOError('Backup mismatch')
                report['backedUp'].append({'path':relative,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
            report['existingUserDirectoryAbsent']=not existing
            (backup/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
            if args.saves:
                root=args.saves.resolve();local_files=sorted(p for p in root.rglob('*') if p.is_file() and p.name!='.DS_Store')
                if not local_files or not any(p.name=='sav.dat' for p in local_files):raise ValueError('No game saves found')
                for local in local_files:
                    if local.is_symlink() or local.name not in {'sav.dat','metadata.9.json','screenshot.png','screenshot.jpg','user.gls'}:
                        raise ValueError('Unexpected save file: '+str(local))
                    relative=local.relative_to(root).as_posix();remote=REMOTE+'/saves/'+relative
                    data=local.read_bytes()
                    if remote in existing and hashlib.sha256(await read(afc,remote)).digest()!=hashlib.sha256(data).digest():
                        raise ValueError('Conflicting phone save was backed up; refusing to overwrite: '+relative)
                    report['imported'].append(await write_verified(afc,remote,data))
            if args.profile:
                data=args.profile.read_bytes();json.loads(data)
                report['profile']=await write_verified(afc,REMOTE+'/UserSettings.json',data)
            await afc.makedirs(REMOTE+'/saves')
    (backup/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v if k not in ('backedUp','imported') else len(v) for k,v in report.items()},ensure_ascii=False,indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--device',required=True);p.add_argument('--bundle-id',required=True)
    p.add_argument('--backup',type=Path,required=True);p.add_argument('--saves',type=Path);p.add_argument('--profile',type=Path)
    asyncio.run(main(p.parse_args()))
