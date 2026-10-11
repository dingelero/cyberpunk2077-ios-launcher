#!/usr/bin/env python3
"""Apply a byte-verified IPA patch offline; never installs or edits app data."""
import argparse,hashlib,json,os,stat,tempfile,zipfile
from pathlib import Path,PurePosixPath

def sha_bytes(data):return hashlib.sha256(data).hexdigest()
def sha_file(path):
    digest=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for data in iter(lambda:stream.read(4*1024*1024),b''):digest.update(data)
    return digest.hexdigest()
def safe_name(name):
    path=PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or '\\' in name or not name.startswith('Payload/CyberpunkRebuilt.app/'):
        raise ValueError('Unsafe IPA entry: '+name)
    return name
def payload_bytes(folder,entry):
    path=(folder/entry['payload']).resolve();path.relative_to(folder.resolve())
    data=path.read_bytes()
    if sha_bytes(data)!=entry['payloadSHA256']:raise ValueError('Patch payload SHA-256 mismatch')
    return data
def patched_bytes(source,entry,folder):
    if entry['operation']=='copy':return source
    data=payload_bytes(folder,entry)
    if entry['operation']=='replace':return data
    if entry['operation']!='ranges':raise ValueError('Unknown patch operation')
    delta=json.loads(data);result=bytearray(source)
    if len(result)<delta['size']:result.extend(bytes(delta['size']-len(result)))
    del result[delta['size']:]
    previous=0
    for change in delta['ranges']:
        offset=change['offset'];replacement=bytes.fromhex(change['hex'])
        if offset<previous or offset+len(replacement)>len(result):raise ValueError('Overlapping or out-of-bounds delta')
        result[offset:offset+len(replacement)]=replacement;previous=offset+len(replacement)
    return bytes(result)
def verify_target(path,manifest):
    target=manifest['target'];files=target['files']
    with zipfile.ZipFile(path) as archive:
        if archive.testzip():raise ValueError('Output IPA CRC mismatch')
        if len(archive.namelist())!=len(files) or set(archive.namelist())!=set(files):raise ValueError('Output IPA file list mismatch')
        for name,entry in files.items():
            data=archive.read(safe_name(name))
            if len(data)!=entry['size'] or sha_bytes(data)!=entry['sha256']:raise ValueError('Output IPA content mismatch: '+name)
    return {'ipa':Path(path).name,'sha256':sha_file(path),'size':Path(path).stat().st_size,
        'fileCount':len(files),'zipCRCAndAllFileSHA256Verified':True,
        'targetVersion':target['version'],'signing':'ad-hoc; user must re-sign app and embedded libraries',
        'installed':False,'appDataModified':False,'sustained30FPSVerified':False}
def apply(base,folder,destination):
    folder=Path(folder).resolve();base=Path(base).resolve();destination=Path(destination).resolve()
    if destination==base:raise ValueError('Original IPA must be kept for rollback')
    manifest=json.loads((folder/'manifest.json').read_text())
    if manifest['format']!='cp2077-ipa-delta-v1':raise ValueError('Unsupported patch manifest')
    digest=sha_file(base)
    variant=next((item for item in manifest['bases'] if item['sha256']==digest),None)
    if variant is None:raise ValueError('Base IPA does not match a supported supplied package. Supported: '+', '.join(x['name'] for x in manifest['bases'])+'. A re-signed IPA is not a matching base.')
    if destination.exists():
        report=verify_target(destination,manifest);print(json.dumps(report,ensure_ascii=False,indent=2));return report
    destination.parent.mkdir(parents=True,exist_ok=True)
    temporary=None
    try:
        with tempfile.NamedTemporaryFile(prefix=destination.name+'.',suffix='.building',dir=destination.parent,delete=False) as stream:temporary=Path(stream.name)
        with zipfile.ZipFile(base) as source,zipfile.ZipFile(temporary,'w',zipfile.ZIP_DEFLATED,compresslevel=6,allowZip64=True) as target:
            if source.testzip():raise ValueError('Base IPA ZIP CRC failure')
            for name,entry in manifest['target']['files'].items():
                safe_name(name);operation=variant['entries'][name]
                original=source.read(name) if operation['sourceExists'] else b''
                if sha_bytes(original)!=operation['sourceSHA256']:raise ValueError('Base entry mismatch: '+name)
                data=patched_bytes(original,operation,folder)
                if len(data)!=entry['size'] or sha_bytes(data)!=entry['sha256']:raise ValueError('Patched entry mismatch: '+name)
                attributes=entry['zip'];info=zipfile.ZipInfo(name,tuple(attributes['date_time']))
                for key in ('create_system','create_version','extract_version','external_attr','internal_attr'):
                    setattr(info,key,attributes[key])
                if stat.S_ISLNK(info.external_attr>>16):raise ValueError('Symlink entries are unsupported')
                target.writestr(info,data,compress_type=zipfile.ZIP_DEFLATED,compresslevel=6)
        report=verify_target(temporary,manifest)
        # Original archive and app resources are never replaced by this tool.
        os.link(temporary,destination);temporary.unlink();temporary=None
        report['ipa']=destination.name
        destination.with_suffix('.patch-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        print(json.dumps(report,ensure_ascii=False,indent=2));return report
    finally:
        if temporary is not None:temporary.unlink(missing_ok=True)
def main():
    default=Path(__file__).resolve().parent
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--patch-folder',type=Path,default=default)
    p.add_argument('--base',type=Path);p.add_argument('--output',type=Path)
    a=p.parse_args();manifest=json.loads((a.patch_folder/'manifest.json').read_text())
    base=a.base
    if base is None:
        for item in manifest['bases']:
            for parent in (a.patch_folder,a.patch_folder.parent):
                candidate=parent/item['name']
                if candidate.is_file() and sha_file(candidate)==item['sha256']:base=candidate;break
            if base is not None:break
    if base is None:raise ValueError('Place a supported original IPA next to the extracted patch folder: '+', '.join(x['name'] for x in manifest['bases'])+', or pass --base /path/to/original.ipa')
    reference=manifest['target'].get('referenceIPA','Cyberpunk2077-patched.ipa')
    name=reference.replace('-candidate.ipa','-patched.ipa')
    if name==reference:name=Path(reference).stem+'-patched.ipa'
    destination=a.output or a.patch_folder.parent/name
    apply(base,a.patch_folder,destination)
if __name__=='__main__':main()
