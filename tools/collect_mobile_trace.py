"""Read saved performance evidence over USB; never launch, stop or update an app."""
import argparse,json
from datetime import datetime
from pathlib import Path
from common import ROOT,write_json
from probe_device import command,DEFAULT_BUNDLE

def analyze(path):
    lines=path.read_text().splitlines();rows=[]
    for i,line in enumerate(lines):
        try:rows.append(json.loads(line))
        except json.JSONDecodeError:
            if i!=len(lines)-1:raise
    if not rows:raise ValueError('No complete trace samples')
    start=rows[-1].get('memory',{}).get('sessionStartedAt')
    pid=rows[-1].get('pid')
    rows=[r for r in rows if r.get('pid')==pid and r.get('memory',{}).get('sessionStartedAt')==start]
    longest=span=0;previous=None;windows=[]
    for row in rows:
        time=row['timestamp']
        if previous is not None:
            gap=time-previous;span=span+gap if 0<gap<=7.5 else 0;longest=max(longest,span)
        previous=time
        timing=row.get('metal',{}).get('presentationTiming',{})
        if timing.get('sampleCount',0)>0:windows.append(timing)
    def peak(field):return max((r.get('memory',{}).get(field,0) or 0 for r in rows),default=0)
    return {'pid':pid,'sessionStartedAt':start,'completeSamples':len(rows),
        'firstSampleTimestamp':rows[0]['timestamp'],'lastSampleTimestamp':rows[-1]['timestamp'],
        'longestContinuouslySampledForegroundSeconds':longest,
        'thermalStatePeak':peak('thermalState'),'physFootprintPeakBytes':peak('physFootprint'),
        'compressedMemoryPeakBytes':peak('compressedBytes'),'metalAllocationPeakBytes':peak('metalAllocatedBytes'),
        'CPUCoreEquivalentPercentPeak':peak('cpuCoreEquivalentPercent'),
        'presentationWindows':len(windows),
        'lowestWindowAveragePresentedFPS':min((w['averagePresentedFPS'] for w in windows),default=None),
        'worstRecordedFrameMilliseconds':max((w['maximumFrameMilliseconds'] for w in windows),default=None),
        'worstWindowP95Milliseconds':max((w['p95FrameMilliseconds'] for w in windows),default=None),
        'startupDisplayPolicy':rows[-1].get('displayPolicy'),
        'lastNativeEngineParameters':rows[-1].get('engine'),
        'nodeBudgetVerifiedSamples':sum(r.get('engine',{}).get('nodeBudgetApplicationVerified') is True for r in rows),
        'scope':'Overlapping native presentation windows, including menus/loading; startup settings snapshot, no scene or live frame-generation inference',
        'gameplayVerified':False,'sustained30FPSFor30MinutesVerified':False}

def collect(destination):
    destination.mkdir(parents=True,exist_ok=True)
    devices=command(['list','devices'],destination/'devices.json')['result']['devices']
    phones=[d for d in devices if d.get('hardwareProperties',{}).get('reality')=='physical' and
        d.get('hardwareProperties',{}).get('deviceType') in ('iPhone','iPad') and d.get('connectionProperties',{}).get('pairingState')=='paired']
    if len(phones)!=1:raise ValueError('请只连接一台已配对、解锁的 iPhone / iPad。')
    device=phones[0]['identifier']
    apps=command(['device','info','apps','--device',device],destination/'apps.json')['result']['apps']
    bundles=[a['bundleIdentifier'] for a in apps if a.get('bundleIdentifier')==DEFAULT_BUNDLE or a.get('bundleIdentifier','').startswith(DEFAULT_BUNDLE+'.')]
    if len(bundles)!=1:raise ValueError('未找到唯一的已安装目标应用。')
    bundle=bundles[0]
    def copy(name):
        if '/' in name or not name.endswith(('.json','.jsonl')):raise ValueError('Unexpected diagnostics filename')
        target=destination/name
        command(['device','copy','from','--device',device,'--domain-type','appDataContainer',
            '--domain-identifier',bundle,'--source','Documents/'+name,'--destination',target],destination/(name+'.copy.json'))
        return target
    host=json.loads(copy('probe-report.json').read_text())
    name=host.get('localPerformanceTrace',{}).get('file')
    if not isinstance(name,str) or not name.startswith('performance-'):raise ValueError('这次启动没有持续性能记录；请安装 mobile-v2 后运行游戏。')
    report=analyze(copy(name));report.update({'readOnlyCollection':True,'installedBundleID':bundle,'launchOrStopPerformed':False})
    write_json(destination/'performance-summary.json',report)
    print(json.dumps(report,ensure_ascii=False,indent=2));print('记录保存在：'+str(destination))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--input',type=Path)
    parser.add_argument('--output',type=Path);args=parser.parse_args()
    try:
        if args.input:print(json.dumps(analyze(args.input),indent=2))
        else:collect(args.output or ROOT/'work/device-startup'/('mobile-v2-'+datetime.now().strftime('%Y%m%d-%H%M%S')))
    except Exception as error:parser.exit(1,'读取失败：'+str(error)+'\n')
