"""Version-checked metadata conversion, derived from Stray-iOS's loader tools.

No instruction rewriting is done here. File offsets stay fixed; removed PAGEZERO
requires a corresponding chained-fixup segment-table correction.
"""
import hashlib, struct

LC_SEGMENT_64=0x19
LC_SYMTAB=2
DYLIB_CMDS={0xc,0xd,0x80000018,0x8000001f,0x80000023}

def commands(data):
    if struct.unpack_from('<II', data) != (0xfeedfacf,0x100000c):
        raise ValueError('Expected thin, ordinary ARM64 Mach-O')
    n, length=struct.unpack_from('<II',data,16)
    p=32
    for _ in range(n):
        c,s=struct.unpack_from('<II',data,p)
        if s<8 or s%8 or p+s>32+length:
            raise ValueError('Malformed load command')
        yield p,c,s
        p+=s
    if p != 32+length: raise ValueError('Malformed command length')

def cstring(data,offset):
    return bytes(data[offset:]).split(b'\0',1)[0].decode()

def sections(data):
    for p,c,s in commands(data):
        if c==LC_SEGMENT_64:
            for i in range(struct.unpack_from('<I',data,p+64)[0]):
                q=p+72+i*80
                yield {'name':cstring(data[q:q+16],0),
                       'segment':cstring(data[q+16:q+32],0),
                       'address':struct.unpack_from('<Q',data,q+32)[0],
                       'size':struct.unpack_from('<Q',data,q+40)[0],
                       'offset':struct.unpack_from('<I',data,q+48)[0]}

def text_hash(data):
    sec=next(s for s in sections(data) if s['name']=='__text')
    return hashlib.sha256(data[sec['offset']:sec['offset']+sec['size']]).hexdigest()

def inspect(data):
    out={'type':struct.unpack_from('<I',data,12)[0], 'textSHA256':text_hash(data),
         'dependencies':[], 'uuid':None, 'entryOffset':None, 'encrypted':False,'platforms':[]}
    import uuid
    for p,c,s in commands(data):
        if c==0x1b: out['uuid']=str(uuid.UUID(bytes=bytes(data[p+8:p+24]))).upper()
        if c==0x80000028: out['entryOffset']=struct.unpack_from('<Q',data,p+8)[0]
        if c==0x2c: out['encrypted'] |= bool(struct.unpack_from('<I',data,p+16)[0])
        if c==0x32: out['platforms'].append(struct.unpack_from('<I',data,p+8)[0])
        if c in DYLIB_CMDS and c!=0xd:
            out['dependencies'].append(cstring(data[p:p+s],struct.unpack_from('<I',data,p+8)[0]))
    return out

def version(v):
    parts=list(map(int,v.split('.')))+[0,0]
    return (parts[0]<<16)|(parts[1]<<8)|parts[2]

def stringcmd(raw,value):
    name=value.encode()+b'\0'
    n=(24+len(name)+7)&~7
    result=bytearray(raw[:24])+name.ljust(n-24,b'\0')
    struct.pack_into('<II',result,4,n,24)
    return result

def convert(original, name, platform, minimum, sdk, remap, main=False, weak_unused=()):
    data=bytearray(original)
    info=inspect(data)
    if info['encrypted']: raise ValueError('Encrypted input is not supported')
    old_text=info['textSHA256']
    old_size=struct.unpack_from('<I',data,20)[0]
    first=min(s['offset'] for s in sections(data) if s['offset'] and s['size'])
    result=[];mapping=[];weakened=[];segments=0;pagezero=False;fixups=None;build=False
    for p,c,s in commands(data):
        raw=bytearray(data[p:p+s])
        if c==LC_SEGMENT_64:
            segments+=1
            if main and cstring(raw[8:24],0)=='__PAGEZERO':
                if segments!=1: raise ValueError('PAGEZERO order unsupported')
                pagezero=True
                continue
        if c==0x80000034: fixups=struct.unpack_from('<II',raw,8)
        if c==0x1d: continue  # Remove original signature metadata; sign the new copy later.
        if main and c in (0xe,0x80000028): continue
        if c in (0x24,0x25,0x2f,0x30,0x32):
            if not build:
                result.append(bytearray(struct.pack('<6I',0x32,24,2 if platform=='ios' else 7,version(minimum),version(sdk),0)))
                build=True
            continue
        if c in DYLIB_CMDS:
            old=cstring(raw,struct.unpack_from('<I',raw,8)[0])
            new='@rpath/'+name if c==0xd else remap(old)
            raw=stringcmd(raw,new)
            if old!=new: mapping.append([old,new])
            if c==0xc and old.rsplit('/',1)[-1] in weak_unused:
                if platform!='iossim': raise ValueError('Weak diagnostic dependencies are simulator-only')
                struct.pack_into('<I',raw,0,0x80000018)
                weakened.append(old)
        if c==LC_SYMTAB:
            stroff,strsize=struct.unpack_from('<II',raw,16)
            if stroff%8:
                pool=bytes(data[stroff:stroff+strsize])
                newoff=(len(data)+7)&~7
                data.extend(b'\0'*(newoff-len(data)))
                data.extend(pool)
                struct.pack_into('<I',raw,16,newoff)
        result.append(raw)
    if not build:
        result.append(bytearray(struct.pack('<6I',0x32,24,2 if platform=='ios' else 7,version(minimum),version(sdk),0)))
    if main:
        result.append(stringcmd(struct.pack('<6I',0xd,24,24,0,0x10000,0x10000),'@rpath/'+name))
    # Ensure all dependent images can find both guest and compatibility libraries.
    rpath=b'@loader_path\0';rlen=(12+len(rpath)+7)&~7
    result.append(bytearray(struct.pack('<III',0x8000001c,rlen,12)+rpath.ljust(rlen-12,b'\0')))
    for raw in result:
        if struct.unpack_from('<I',raw)[0]==LC_SEGMENT_64 and cstring(raw[8:24],0)=='__LINKEDIT':
            fileoff=struct.unpack_from('<Q',raw,40)[0]
            size=len(data)-fileoff
            struct.pack_into('<Q',raw,48,size)
            struct.pack_into('<Q',raw,32,(size+0x3fff)&~0x3fff)
    blob=b''.join(result)
    if 32+len(blob)>first: raise ValueError('Insufficient Mach-O header slack')
    data[32:32+max(old_size,len(blob))]=blob.ljust(max(old_size,len(blob)),b'\0')
    struct.pack_into('<III',data,12,6 if main else info['type'],len(result),len(blob))
    if main:
        struct.pack_into('<I',data,24,struct.unpack_from('<I',data,24)[0]&~0x200000)
    if pagezero and fixups:
        start,size=fixups
        table=start+struct.unpack_from('<I',data,start+4)[0]
        count=struct.unpack_from('<I',data,table)[0]
        values=struct.unpack_from('<'+'I'*count,data,table+4)
        if count!=segments or values[0]!=0 or table+4+count*4>start+size:
            raise ValueError('Unsupported chained-fixup PAGEZERO table')
        struct.pack_into('<I',data,table,count-1)
        struct.pack_into('<'+'I'*count,data,table+4,*values[1:],0)
    if text_hash(data)!=old_text: raise ValueError('Metadata conversion changed CPU instructions')
    return data,{'input':info,'dependencyMappings':mapping,'textPreserved':True,
                 'simulatorOnlyWeakUnusedDependencies':weakened,
                 'removedPAGEZERO':pagezero,'chainedFixupTableAdjusted':bool(pagezero and fixups),
                 'convertedType':struct.unpack_from('<I',data,12)[0]}
