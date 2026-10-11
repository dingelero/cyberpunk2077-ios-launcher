#!/usr/bin/env python3
"""Fetch and safely extract the exact official curl/OpenSSL source inputs.

Existing verified archives and extracted source trees are reused without network
access. Archives are authenticated by the fixed SHA-256 used in build_curl.py.
"""
import argparse, hashlib, json, os, shutil, tarfile, tempfile, urllib.request
from pathlib import Path, PurePosixPath
from common import ROOT, sha, write_json
from build_curl import SOURCES

URLS={
    'curl':'https://curl.se/download/curl-8.22.0.tar.xz',
    'openssl':'https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz',
}
LICENCES={
    'curl':('COPYING','curl-COPYING.txt'),
    'openssl':('LICENSE.txt','openssl-LICENSE.txt'),
}

def obtain_archive(component,details,vendor):
    destination=vendor/details['archive']
    if destination.exists():
        if sha(destination)!=details['sha256']:
            raise ValueError('Existing archive hash mismatch; refusing to reuse or overwrite '+str(destination))
        return destination,False
    temporary=destination.with_name(destination.name+'.download')
    digest=hashlib.sha256()
    request=urllib.request.Request(URLS[component],headers={'User-Agent':'CyberpunkRebuilt-dependency-fetch/1'})
    try:
        with urllib.request.urlopen(request,timeout=60) as response,temporary.open('wb') as stream:
            while True:
                block=response.read(1024*1024)
                if not block:break
                stream.write(block);digest.update(block)
            stream.flush();os.fsync(stream.fileno())
        if digest.hexdigest()!=details['sha256']:
            raise ValueError('Downloaded archive SHA-256 mismatch: '+URLS[component])
        temporary.replace(destination)
        return destination,True
    finally:
        if temporary.exists():temporary.unlink()

def safe_members(archive,expected_top):
    members=archive.getmembers()
    for member in members:
        path=PurePosixPath(member.name)
        if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0]!=expected_top:
            raise ValueError('Unsafe or unexpected archive path: '+member.name)
        # Both pinned official archives contain only regular files/directories.
        # Reject links, devices, FIFOs and any future unexpected member type.
        if not (member.isfile() or member.isdir()):
            raise ValueError('Unsupported archive member type: '+member.name)
    return members

def extract_verified(archive,component,details,vendor):
    top=component+'-'+details['version'];destination=vendor/top
    marker=destination/'.cp2077-source.json'
    expected={'archive':details['archive'],'sha256':details['sha256'],'sourceURL':URLS[component]}
    if marker.exists() and json.loads(marker.read_text())==expected:
        return destination,False
    with tempfile.TemporaryDirectory(prefix='.cp2077-extract-',dir=vendor) as temporary:
        staging=Path(temporary)
        with tarfile.open(archive,'r:*') as source:
            members=safe_members(source,top)
            # Manual extraction does not interpret links or restore archive
            # owners/modes. Files are created under a fresh temporary directory.
            for member in members:
                path=staging/Path(*PurePosixPath(member.name).parts)
                if member.isdir():path.mkdir(parents=True,exist_ok=True);continue
                path.parent.mkdir(parents=True,exist_ok=True)
                with source.extractfile(member) as input_file,path.open('wb') as output_file:
                    shutil.copyfileobj(input_file,output_file,1024*1024)
                path.chmod(0o755 if member.mode&0o111 else 0o644)
        unpacked=staging/top
        if destination.exists():
            # The provided trees predate this fetcher. Reuse them only after
            # comparing every archive file to the authenticated clean tree.
            for item in unpacked.rglob('*'):
                relative=item.relative_to(unpacked);current=destination/relative
                if item.is_dir():
                    if not current.is_dir() or current.is_symlink():
                        raise ValueError('Existing source directory mismatch: '+str(current))
                elif not current.is_file() or current.is_symlink() or sha(item)!=sha(current):
                    raise ValueError('Existing source content mismatch: '+str(current))
            reused=True
        else:
            unpacked.replace(destination);reused=False
        write_json(marker,expected)
        return destination,not reused

def fetch(only=None):
    vendor=ROOT/'vendor';vendor.mkdir(parents=True,exist_ok=True);report=[]
    for component,details in SOURCES.items():
        if only and component!=only:continue
        archive,downloaded=obtain_archive(component,details,vendor)
        source,extracted=extract_verified(archive,component,details,vendor)
        original,output_name=LICENCES[component]
        if not (source/original).is_file():raise ValueError('Dependency licence missing: '+str(source/original))
        shutil.copy2(source/original,ROOT/output_name)
        record={'component':component,'version':details['version'],'sourceURL':URLS[component],
                'archiveSHA256':details['sha256'],'downloaded':downloaded,'extracted':extracted,
                'source':str(source.relative_to(ROOT)),'licence':output_name}
        report.append(record);print(json.dumps(record),flush=True)
    write_json(ROOT/'evidence/dependency-fetch.json',report)
    return report

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--only',choices=['curl','openssl']);arguments=parser.parse_args();fetch(arguments.only)
