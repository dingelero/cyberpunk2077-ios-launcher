#!/usr/bin/env python3
"""Read small native frame reports over USB without attaching a debugger."""
import argparse,asyncio,json,time,os,tempfile
from pathlib import Path
from user_data import REMOTE
from common import env

async def read_snapshot(afc,path):
    # Open before sizing: the host atomically replaces its report. A path stat
    # followed by open can size the old inode and read the new one incompletely.
    handle=await afc.fopen(path,'r')
    try:
        await afc.fseek(handle,0,os.SEEK_END);size=await afc.ftell(handle)
        if size>64*1024*1024:raise ValueError('Unexpectedly large diagnostic file')
        await afc.fseek(handle,0,os.SEEK_SET);chunks=[]
        while size:
            data=await afc.fread(handle,min(size,1024*1024))
            if not data:raise IOError('Short diagnostic read')
            chunks.append(data);size-=len(data)
        return b''.join(chunks)
    finally:await afc.fclose(handle)

async def read_json_snapshot(afc,path):
    for attempt in range(3):
        try:return json.loads(await read_snapshot(afc,path))
        except (json.JSONDecodeError,UnicodeDecodeError):
            if attempt==2:raise
            await asyncio.sleep(.15)

class CoreDeviceReader:
    """Only copies the two small files in this app's container; never pairs."""
    def __init__(self,args):
        self.args=args
        self.directory=tempfile.TemporaryDirectory(prefix='cp2077-frame-snapshot-')
        self.sequence=0

    async def read(self,path):
        self.sequence+=1
        directory=Path(self.directory.name)
        destination=directory/f'{self.sequence}.json'
        receipt=directory/f'{self.sequence}-operation.json'
        process=await asyncio.create_subprocess_exec('xcrun','devicectl','--timeout','10',
            '--json-output',str(receipt),'device','copy','from','--device',self.args.device,
            '--domain-type','appDataContainer','--domain-identifier',self.args.bundle_id,
            '--source',path.lstrip('/'),'--destination',str(destination),env=env(),
            stdout=asyncio.subprocess.DEVNULL,stderr=asyncio.subprocess.PIPE)
        try:
            _,error=await asyncio.wait_for(process.communicate(),15)
        except asyncio.TimeoutError:
            process.kill();await process.communicate()
            raise TimeoutError('CoreDevice did not acknowledge the snapshot operation')
        # A file may have arrived even when the operation failed. Do not treat
        # that as a successful copy or silently accept a previous report.
        if process.returncode:
            raise RuntimeError(f'CoreDevice snapshot operation returned {process.returncode}')
        operation=json.loads(receipt.read_text())
        if operation.get('info',{}).get('outcome')!='success':
            raise RuntimeError('CoreDevice snapshot receipt did not confirm success')
        data=destination.read_bytes()
        if len(data)>64*1024*1024:raise ValueError('Unexpectedly large diagnostic file')
        destination.unlink();receipt.unlink()
        return json.loads(data)

    def close(self):self.directory.cleanup()

def save(path,result):
    temporary=path.with_suffix(path.suffix+'.tmp')
    temporary.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');temporary.replace(path)

async def sample(args):
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.services.house_arrest import HouseArrestService
    args.output.parent.mkdir(parents=True,exist_ok=True)
    result={'scope':args.scene,'debuggerAttachedByThisTool':False,'samples':[],
        'sceneVerifiedByThisTool':False,'sustained30FPSVerified':False,'samplingComplete':False}
    reader=None;lockdown=None;afc=None
    try:
        if args.transport!='coredevice':
            try:
                lockdown=await create_using_usbmux(serial=args.device,connection_type='USB',autopair=False,
                    pairing_records_cache_folder=Path(__file__).resolve().parents[1]/'work/pairing-cache')
                afc=await HouseArrestService.create(lockdown,args.bundle_id,documents_only=False)
            except Exception as error:
                if lockdown:await lockdown.close();lockdown=None
                if args.transport=='afc':raise
                result['afcConnectionError']=type(error).__name__
        if afc:
            async def read(path):return await read_json_snapshot(afc,path)
            result['transport']='afc'
        else:
            reader=CoreDeviceReader(args);read=reader.read;result['transport']='coredevice'
        started=time.monotonic();settings=None;settings_at=0;failures=0
        save(args.output,result)
        try:
            while time.monotonic()-started<args.seconds:
                try:
                    host=await read('/Documents/probe-report.json')
                    if settings is None or time.monotonic()-settings_at>=10:
                        settings=await read(REMOTE+'/UserSettings.json');settings_at=time.monotonic()
                    failures=0
                except Exception as error:
                    failures+=1
                    result.setdefault('samplingErrors',[]).append({'at':time.time(),'error':type(error).__name__+': '+str(error)})
                    save(args.output,result)
                    if failures>=3:raise
                    await asyncio.sleep(2);continue
                names={'Resolution','MaximumFPS_OnOff','MaximumFPS_Value','ResolutionScaling',
                    'FSR2','MetalFX','FSR3','FrameGeneration','FSR3_FrameGeneration','HDRModes'}
                selected={o['name']:o['value'] for g in settings['data'] for o in g['options'] if o['name'] in names}
                collected=time.time();updated=host.get('updatedAt')
                result['samples'].append({'collectedAt':collected,'pid':host.get('pid'),'reportUpdatedAt':updated,
                    'reportAgeSeconds':collected-updated if isinstance(updated,(int,float)) else None,
                    'launchState':host.get('launchState'),'settings':selected,'metal':host.get('metalRuntime'),
                    'memory':host.get('latestMemorySample'),'appKit':host.get('appKitBridge')})
                save(args.output,result)
                last=result['samples'][-1];timing=(last['metal'] or {}).get('presentationTiming',{})
                print(json.dumps({'sample':len(result['samples']),'pid':last['pid'],'settings':selected,'timing':timing},ensure_ascii=False),flush=True)
                await asyncio.sleep(args.interval)
            result['samplingComplete']=True
        finally:
            result['elapsedSeconds']=time.monotonic()-started
            pids={s['pid'] for s in result['samples']}
            modes={json.dumps(s['settings'],sort_keys=True) for s in result['samples']}
            result['sameProcess']=len(pids)==1;result['settingsUnchanged']=len(modes)==1
            save(args.output,result)
    finally:
        if afc:await afc.close()
        if lockdown:await lockdown.close()
        if reader:reader.close()

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--device',required=True);p.add_argument('--bundle-id',required=True)
    p.add_argument('--output',type=Path,required=True);p.add_argument('--seconds',type=float,default=60)
    p.add_argument('--transport',choices=['auto','afc','coredevice'],default='auto')
    p.add_argument('--interval',type=float,default=2)
    p.add_argument('--scene',default='Unclassified; verify through device screen separately')
    asyncio.run(sample(p.parse_args()))
