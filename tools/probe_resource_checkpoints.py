#!/usr/bin/env python3
"""Fault-inject AFC readback caches locally; does not connect to a device."""
import asyncio, hashlib, json, tempfile
from pathlib import Path
import transfer_resources as t

DATA = bytes(range(256)) * (t.IO_BYTES * 4 // 256)

class AFC:
    def __init__(self, data=DATA, identity='1', fail_at=None, identity_available=True):
        self.data=data; self.identity=identity; self.fail_at=fail_at
        self.offset=0; self.seeks=[]; self.reads=0; self.identity_available=identity_available
    async def stat(self, path):
        result={'st_size':len(self.data),'st_ifmt':'S_IFREG'}
        if self.identity_available: result.update(st_ino=self.identity,st_mtime=self.identity)
        return result
    async def fopen(self, path, mode): self.offset=0; return 1
    async def fseek(self, handle, offset, whence): self.offset=offset; self.seeks.append(offset)
    async def fread(self, handle, count):
        if self.fail_at is not None and self.offset >= self.fail_at:
            raise ConnectionResetError('injected transport reset')
        result=self.data[self.offset:self.offset+count]
        self.offset+=len(result); self.reads+=len(result); return result
    async def fclose(self, handle): pass

async def expect_reset(operation):
    try: await operation
    except ConnectionResetError: return
    raise AssertionError('Transport reset did not propagate')

async def probe():
    cases=[]; expected=hashlib.sha256(DATA).hexdigest()
    changed=bytes([DATA[0]^1])+DATA[1:]
    t.HASH_CHECKPOINTS.clear(); t.PREFIX_CHECKPOINTS.clear()
    await expect_reset(t.remote_hash(AFC(fail_at=t.IO_BYTES*2),'hash',len(DATA),'test'))
    fresh=AFC(); actual=await t.remote_hash(fresh,'hash',len(DATA),'test')
    assert actual==expected and fresh.seeks==[t.IO_BYTES*2] and fresh.reads==t.IO_BYTES*2
    cases.append('same native identity resumes hash with full SHA256 match')
    await expect_reset(t.remote_hash(AFC(fail_at=t.IO_BYTES),'changed',len(DATA),'test'))
    fresh=AFC(changed,identity='2'); actual=await t.remote_hash(fresh,'changed',len(DATA),'test')
    assert actual==hashlib.sha256(changed).hexdigest() and actual!=expected and fresh.reads==len(DATA) and fresh.seeks==[]
    cases.append('changed inode or mtime discards stale digest and detects changed data')
    await expect_reset(t.remote_hash(AFC(fail_at=t.IO_BYTES,identity_available=False),'no-identity',len(DATA),'test'))
    fresh=AFC(identity_available=False); actual=await t.remote_hash(fresh,'no-identity',len(DATA),'test')
    assert actual==expected and fresh.reads==len(DATA) and fresh.seeks==[]
    cases.append('missing native identity forces full hash restart')
    with tempfile.TemporaryDirectory() as folder:
        source=Path(folder)/'bytes.bin'; source.write_bytes(DATA)
        await expect_reset(t.prefix_matches(AFC(fail_at=t.IO_BYTES*2),'prefix',source,len(DATA)))
        fresh=AFC(); assert await t.prefix_matches(fresh,'prefix',source,len(DATA))
        assert fresh.seeks==[t.IO_BYTES*2] and fresh.reads==t.IO_BYTES*2
        cases.append('same identity resumes byte-for-byte prefix comparison')
        await expect_reset(t.prefix_matches(AFC(fail_at=t.IO_BYTES),'prefix-change',source,len(DATA)))
        fresh=AFC(changed,identity='2'); assert not await t.prefix_matches(fresh,'prefix-change',source,len(DATA))
        assert fresh.seeks==[]
        cases.append('changed identity restarts prefix and rejects incorrect bytes')
        await expect_reset(t.prefix_matches(AFC(fail_at=t.IO_BYTES),'local-change',source,len(DATA)))
        source.write_bytes(changed); fresh=AFC()
        assert not await t.prefix_matches(fresh,'local-change',source,len(DATA)) and fresh.seeks==[]
        cases.append('local file mutation discards cached prefix')
    report={'passed':len(cases),'cases':cases,'physicalDeviceTest':False}
    destination=Path(__file__).resolve().parents[1]/'evidence/afc-hash-checkpoint-tests.json'
    destination.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__': asyncio.run(probe())
