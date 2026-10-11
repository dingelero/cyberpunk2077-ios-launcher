#!/usr/bin/env python3
"""Launch the installed, user-signed app and collect scoped startup evidence."""
import argparse,json,subprocess,time
from datetime import datetime
from pathlib import Path
from common import ROOT,env,write_json

DEFAULT_BUNDLE='local.cyberpunk.ios.rebuilt'

def command(argv, destination, capture=None):
    call=['xcrun','devicectl','--json-output',str(destination),*map(str,argv)]
    if capture:
        with capture.open('w') as log:
            result=subprocess.run(call,env=env(),stdout=log,stderr=subprocess.STDOUT)
    else:
        result=subprocess.run(call,env=env(),capture_output=True,text=True,timeout=45)
        destination.with_suffix('.command.log').write_text(result.stdout+'\n'+result.stderr)
    if result.returncode:raise RuntimeError('CoreDevice operation failed; inspect '+str(destination.parent))
    return json.loads(destination.read_text()) if destination.exists() else {}

def complete_resources(path):
    value=json.loads(path.read_text())
    files=value.get('files',[])
    complete=(value.get('status')=='complete' and value.get('device_verified') is True and
        value.get('expected_files',0)>0 and value.get('verified_files')==value.get('expected_files')==len(files) and
        all(f.get('device_verified') is True and len(f.get('sha256',''))==64 for f in files))
    if not complete:raise RuntimeError('资源仍在导入或未完成设备 SHA-256 校验；此次不启动游戏、不读取应用容器。')
    return {k:value.get(k) for k in ['scope','verified_files','verified_bytes','expected_files','expected_bytes']}

def probe(arguments):
    capture=arguments.capture_dir or ROOT/'work/device-startup'/datetime.now().strftime('%Y%m%d-%H%M%S')
    capture.mkdir(parents=True,exist_ok=True)
    report={'scope':'Physical iPhone startup diagnostics, not gameplay acceptance','launchPerformed':False,'gameplayVerified':False}
    resource=None
    if not arguments.preflight_only:resource=complete_resources(arguments.resource_report)
    devices=command(['list','devices'],capture/'devices-raw.json')['result']['devices']
    phones=[d for d in devices if d.get('hardwareProperties',{}).get('reality')=='physical' and
        d.get('hardwareProperties',{}).get('deviceType')=='iPhone' and d.get('connectionProperties',{}).get('pairingState')=='paired']
    if arguments.device:phones=[d for d in phones if arguments.device in (d.get('identifier'),d.get('hardwareProperties',{}).get('udid'))]
    if len(phones)!=1:raise RuntimeError('请只连接一台已配对的 iPhone，或用 --device 指定目标。')
    device=phones[0];identifier=device['identifier']
    details=command(['device','info','details','--device',identifier],capture/'device-details-raw.json')['result']
    software=details.get('softwareProperties',details.get('deviceProperties',{}))
    developer=details.get('deviceProperties',{}).get('developerModeStatus')
    applications=command(['device','info','apps','--device',identifier],capture/'apps-raw.json')['result']['apps']
    candidates=[a['bundleIdentifier'] for a in applications if a.get('bundleIdentifier')==arguments.bundle_id or
        (arguments.bundle_id==DEFAULT_BUNDLE and a.get('bundleIdentifier','').startswith(DEFAULT_BUNDLE+'.'))]
    if len(candidates)!=1:raise RuntimeError('未找到唯一的已安装目标应用；请用 --bundle-id 指定签名后的 ID。')
    bundle=candidates[0]
    report.update({'deviceModel':device['hardwareProperties'].get('productType'),
        'osVersion':software.get('osVersionNumber'),'developerModeStatus':developer,'installedBundleID':bundle})
    if arguments.preflight_only:
        report['preflightOnly']=True;write_json(capture/'report.json',report);print(json.dumps(report,ensure_ascii=False,indent=2));return
    report['resources']=resource;started=time.time()
    try:
        if not arguments.collect_only:
            print('开始真机启动并记录控制台。Ctrl-C 会向游戏转发终止信号；请先在手机结束测试。',flush=True)
            report['launchPerformed']=True
            launch=command(['device','process','launch','--device',identifier,'--terminate-existing','--console',
                '--environment-variables',json.dumps({'CP2077_TRACE_VM':'1','CP2077_TRACE_PATH':'1','MTL_HUD_ENABLED':'1','MTL_HUD_LOG_ENABLED':'1'}),
                bundle,'--trace-memory','--trace-controller'],capture/'launch-raw.json',capture/'console.log')
            report['launchedPID']=launch.get('result',{}).get('process',{}).get('processIdentifier')
            report['terminationResult']=launch.get('result',{}).get('terminationResult')
    except (RuntimeError,KeyboardInterrupt) as error:
        report['launchOrConsoleError']=type(error).__name__+': '+str(error)
    finally:
        for name in ['probe-report.json','runtime.log','memory-report.json']:
            try:
                command(['device','copy','from','--device',identifier,'--domain-type','appDataContainer',
                    '--domain-identifier',bundle,'--source','Documents/'+name,'--destination',capture/name],capture/(name+'.copy-raw.json'))
            except Exception as error:report.setdefault('collectionErrors',{})[name]=str(error)
        path=capture/'probe-report.json'
        if path.is_file():
            host=json.loads(path.read_text())
            report.update({'hostPID':host.get('pid'),'hostReportFromThisLaunch':report['launchPerformed'] and
                report.get('launchedPID')==host.get('pid') and host.get('startedAt',0)>=started,
                'launchState':host.get('launchState'),'launchFailure':host.get('launchFailure'),'guestEntryCalled':host.get('guestEntryCalled'),
                'metalCapabilities':host.get('metalNativeCapabilities'),'latestMemorySample':host.get('latestMemorySample')})
            exception=host.get('uncaughtObjectiveCException')
            if exception:
                report.update({'launchStateFromHost':report['launchState'],'launchState':'failed_due_to_uncaught_exception',
                    'uncaughtObjectiveCException':{k:exception.get(k) for k in ['name','reason']}})
        write_json(capture/'report.json',report)
    print(json.dumps(report,ensure_ascii=False,indent=2));print('本次诊断目录：'+str(capture))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resource-report',type=Path,default=ROOT.parent/'resource-import/resource-transfer-report.json')
    parser.add_argument('--capture-dir',type=Path);parser.add_argument('--device');parser.add_argument('--bundle-id',default=DEFAULT_BUNDLE)
    mode=parser.add_mutually_exclusive_group();mode.add_argument('--preflight-only',action='store_true');mode.add_argument('--collect-only',action='store_true')
    try:probe(parser.parse_args())
    except Exception as error:parser.exit(1,str(error)+'\n')
