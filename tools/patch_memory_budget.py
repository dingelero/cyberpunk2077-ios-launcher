"""Apply exactly the four version-locked capacity changes from the supplied report."""
import argparse,struct
from common import ROOT,config,sha,output,write_json
from macho import inspect,text_hash
PATCHES=[(0xf6f8,0xd2c00209,0xd2c00049),(0xf73c,0xd2c00109,0xd2c00049),
         (0x20cad18,0xd2c00028,0xd2a80008),(0x20cad98,0xd2c00028,0xd2a80008)]

def patch(platform):
    cfg=config();path=output(platform)/'prepared/CyberpunkGuest.dylib';data=bytearray(path.read_bytes())
    info=inspect(data)
    if info['uuid']!=cfg['game_uuid']: raise ValueError('Unsupported UUID')
    if info['textSHA256']==cfg['memory_patch_text_sha256']: return
    if info['textSHA256']!=cfg['original_text_sha256']: raise ValueError('Unexpected original instructions')
    changes=[]
    for offset,old,new in PATCHES:
        if struct.unpack_from('<I',data,offset)[0]!=old: raise ValueError('Patch input mismatch')
        struct.pack_into('<I',data,offset,new)
        changes.append({'offset':hex(offset),'old':hex(old),'new':hex(new)})
    after=text_hash(data)
    if after!=cfg['memory_patch_text_sha256']: raise ValueError('Unexpected patched instruction hash')
    path.write_bytes(data)
    run_report={'uuid':info['uuid'],'beforeTextSHA256':info['textSHA256'],'afterTextSHA256':after,
                'instructionChanges':changes,'gameplayVerified':False,'iPhoneMemoryBudgetVerified':False}
    write_json(output(platform)/'memory-patch.json',run_report)
    print('Applied exactly four capacity instructions; final __text hash matches supplied report.')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--platform',choices=['ios','iossim'],default='ios');a=p.parse_args();patch(a.platform)
