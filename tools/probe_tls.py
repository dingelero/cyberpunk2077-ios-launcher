#!/usr/bin/env python3
"""Native simulator TLS probe; records network failure without treating it as trust success."""
import argparse,json,subprocess
from pathlib import Path
from common import ROOT,env,config,run,write_json

def probe(udid):
    sdk=run(['xcrun','--sdk','iphonesimulator','--show-sdk-path']).strip()
    directory=ROOT/'work/tls-smoke';directory.mkdir(parents=True,exist_ok=True)
    binary=directory/'tls-smoke'
    library=ROOT/'build/iossim/compat'
    logs=ROOT/'evidence/tls'
    run(['xcrun','--sdk','iphonesimulator','clang','-target','arm64-apple-ios18.0-simulator',
         '-isysroot',sdk,'-O2',ROOT/'work/tls-smoke.c','-I',ROOT/'vendor/curl-8.22.0/include',
         '-L',library,'-lCPCurl','-Wl,-rpath,'+str(library),'-o',binary],logfile=logs/'runtime-simulator-compile.log')
    run(['codesign','--force','--sign','-',binary],logfile=logs/'runtime-simulator-codesign.log')
    launched=subprocess.run(['xcrun','simctl','spawn',udid,str(binary)],env=env(),text=True,
        stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
    (logs/'runtime-simulator-stdout.log').write_text(launched.stdout)
    (logs/'runtime-simulator-stderr.log').write_text(launched.stderr)
    report={'simulatorUDID':udid,'exitCode':launched.returncode,'platform':'iOSSimulator arm64',
            'scope':'Native simulator curl/OpenSSL/SecTrust only; no Steam, device, or gameplay claim',
            'positiveHTTPSVerified':False,'expiredCertificateRejected':False}
    if launched.returncode==0:
        try:
            result=json.loads(launched.stdout.strip());report.update(result)
            positive,expired,default_positive,default_expired=result['requests']
            report['positiveHTTPSVerified']=positive['result']==0 and 200<=positive['httpCode']<400
            report['expiredCertificateRejected']=expired['result']==60
            report['defaultPositiveHTTPSVerified']=default_positive['result']==0 and 200<=default_positive['httpCode']<400
            report['defaultExpiredCertificateRejected']=default_expired['result']==60
        except (ValueError,KeyError,IndexError) as error:report['parseError']=str(error)
    else:report['launchError']=launched.stderr[-4000:]
    write_json(logs/'runtime-simulator.json',report)
    built_report=logs/'iossim/build-report.json'
    if built_report.exists():
        built=json.loads(built_report.read_text())
        built['runtimeTLSVerified']=bool(report['positiveHTTPSVerified'] and report['expiredCertificateRejected'] and report.get('defaultPositiveHTTPSVerified') and report.get('defaultExpiredCertificateRejected'))
        built['runtimeEvidence']='evidence/tls/runtime-simulator.json'
        built['runtimeScope']='Native arm64 iOS Simulator, not iPhone hardware or Steam'
        write_json(built_report,built)
    print(json.dumps(report,ensure_ascii=False,indent=2))
    return report

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--udid',default='<simulator-device>');a=p.parse_args();probe(a.udid)
