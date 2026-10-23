import io,math,random,struct,subprocess,sys,wave
rng=random.Random(0x7a7e2026)
def chunk(tag,data,pad=0):return tag+struct.pack('<I',len(data))+data+(bytes([pad]) if len(data)%2 else b'')
def riff(chunks):
    data=b'WAVE'+b''.join(chunks)
    return b'RIFF'+struct.pack('<I',len(data))+data
def make(width,ch,values,floating=False,valid=None,mask=0,unknown=False):
    rate=48000;align=ch*width//8;tag=3 if floating else 1
    fmt=struct.pack('<HHIIHH',tag,ch,rate,rate*align,align,width)
    if valid is not None:
        fmt=struct.pack('<HHIIHHHHI',65534,ch,rate,rate*align,align,width,22,valid,mask)
        fmt+=struct.pack('<I',tag)+bytes.fromhex('00001000800000aa00389b71')
    elif floating:fmt+=b'\0\0'
    if floating:data=b''.join(struct.pack('<f' if width==32 else '<d',x) for x in values)
    else:data=b''.join(((x+128) if width==8 else x%(1<<width)).to_bytes(width//8,'little') for x in values)
    chunks=[chunk(b'fmt ',fmt)]
    if unknown:chunks += [chunk(b'JUNK',b'xyz',213),chunk(b'LIST',b'INFO')]
    if floating:chunks += [chunk(b'fact',struct.pack('<I',len(values)//ch))]
    chunks += [chunk(b'data',data)]
    if unknown:chunks += [chunk(b'abcd',b'12345',67)]
    return riff(chunks)
cases=[]
def add(data,want=None,width=16,ch=1,floating=False,valid=None,mask=0,out=0,maxbytes=4000000,maxsamples=1000000,maxout=4000000,error=None):
    cases.append(dict(data=data,want=want,width=width,ch=ch,floating=floating,valid=valid or width,mask=mask if valid is not None else 0,out=out,maxbytes=maxbytes,maxsamples=maxsamples,maxout=maxout,error=error))
for width in [8,16,24,32]:
    for ch in [1,2,3,6]:
        for valid in [None,width,max(1,width-5)]:
            quantum=1<<(width-(valid or width));lo=-(1<<(width-1));hi=(1<<(width-1))-quantum
            values=[lo,hi,0,-quantum,quantum]*(ch*3)
            values += [rng.randrange(lo//quantum,hi//quantum+1)*quantum for _ in range(ch*31)]
            mask=3 if ch==2 else 0
            src=make(width,ch,values,valid=valid,mask=mask,unknown=True)
            want=[v/(1<<(width-1)) for v in values]
            for output in [0,8,16,24,32,132,164]:add(src,want,width,ch,valid=valid,mask=mask,out=output)
        add(make(width,ch,[]),[],width,ch)
for width in [32,64]:
    for ch in [1,2,5]:
        values=[0.,-0.,1.,-1.,.5,-.125,3.25,1e-30,-1e30]*ch
        values += [rng.uniform(-2,2) for _ in range(ch*31)]
        if width==32:values=[struct.unpack('<f',struct.pack('<f',v))[0] for v in values]
        else:values += [sys.float_info.max,-sys.float_info.max,math.ulp(0.)]*ch
        for valid in [None,width]:
            src=make(width,ch,values,True,valid,0,True)
            for output in [0,16,24,164]:add(src,values,width,ch,True,valid,out=output)
        for bad in [math.nan,math.inf,-math.inf]:add(make(width,ch,[bad]*ch,True),error=10)
# Lossless exhaustive PCM8 and PCM16 endpoints, representative PCM24/32 codes.
for width in [8,16,24,32]:
    values=list(range(-128,128)) if width==8 else list(range(-32768,32768)) if width==16 else [-(1<<(width-1)),(1<<(width-1))-1,-1,0,1]+[rng.randrange(-(1<<(width-1)),1<<(width-1)) for _ in range(8000)]
    add(make(width,1,values),[v/(1<<(width-1)) for v in values],width)
base=make(16,2,[-32768,32767,0,1],unknown=True)
for end in range(len(base)):add(base[:end],error=-1)
for offset,value,error in [(0,b'RIFX',3),(8,b'NOPE',3),(4,struct.pack('<I',0xffffffff),3),(22,b'\0\0',7),(24,b'\0'*4,7),(28,b'\0'*4,7),(32,b'\1\0',7),(34,b'\x0c\0',8)]:
    b=bytearray(base);b[offset:offset+len(value)]=value;add(bytes(b),error=error)
fmt=chunk(b'fmt ',struct.pack('<HHIIHH',1,1,48000,96000,2,16))
add(riff([fmt,fmt,chunk(b'data',b'')]),error=5)
add(riff([fmt,chunk(b'data',b''),chunk(b'data',b'')]),error=5)
add(riff([fmt]),error=6)
add(riff([chunk(b'data',b'')]),error=6)
add(riff([chunk(b'data',b''),fmt]),error=7)
add(riff([fmt,chunk(b'data',b'x')]),error=7)
add(riff([fmt,chunk(b'fact',struct.pack('<I',1)),chunk(b'data',b'')]),error=7)
add(riff([fmt,chunk(b'fact',b'x'),chunk(b'data',b'')]),error=4)
ext=bytearray(make(24,1,[0,32],valid=19));ext[-3]=1;add(bytes(ext),error=12)
ext=bytearray(make(24,1,[0],valid=19));ext[44]=99;add(bytes(ext),error=8)
add(base,maxbytes=len(base)-1,error=9)
add(base,maxsamples=3,error=9)
add(base,[-1.,32767/32768,0.,1/32768],16,2,maxout=1)
# 400k frames validates linear bulk codec workload, with unknown chunks.
large=[((i*31337)%65536)-32768 for i in range(400000)]
add(make(16,1,large,unknown=True),[v/32768 for v in large],16)
packet=b''.join(struct.pack('<5i',len(c['data']),c['maxbytes'],c['maxsamples'],c['out'],c['maxout'])+c['data'] for c in cases)
r=subprocess.run([sys.argv[1]],input=packet,capture_output=True,timeout=35)
assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr,len(r.stdout))
at=0
def take(n):
    global at
    b=r.stdout[at:at+n];assert len(b)==n;at+=n;return b
def integer():return struct.unpack('<i',take(4))[0]
def chunks(b):
    assert b[:4]==b'RIFF' and b[8:12]==b'WAVE' and len(b)==8+int.from_bytes(b[4:8],'little')
    at=12;out={}
    while at<len(b):
        tag=b[at:at+4];n=int.from_bytes(b[at+4:at+8],'little');at+=8
        assert n<=len(b)-at and tag not in out
        out[tag]=b[at:at+n];at+=n
        if n%2:assert b[at]==0;at+=1
    assert at==len(b);return out
for idx,c in enumerate(cases):
    status=integer();label=('seed=0x7a7e2026',idx,c['width'],c['ch'],c['out'])
    if c['error'] is not None:
        assert status==(c['error'] if c['error']>=0 else status) and status>0,(label,status,c['error']);continue
    assert status==0,(label,status)
    ch,rate,frames,width,valid,mask,ex=struct.unpack('<7i',take(28))
    assert (ch,rate,frames,width,valid,mask)==(c['ch'],48000,len(c['want'])//c['ch'],c['width'],c['valid'],c['mask']),(label,ch,rate,frames,width,valid,mask)
    assert ex==int(c['data'][20:22]==b'\xfe\xff'),(label,'extensible',ex)
    got=list(struct.unpack('<'+'d'*len(c['want']),take(8*len(c['want']))))
    assert got==c['want'],(label,got[:10],c['want'][:10])
    encoded_n=integer()
    if c['maxout']==1:assert encoded_n==-9;continue
    assert encoded_n>=0,(label,encoded_n)
    b=take(encoded_n);parts=chunks(b);fmt=parts[b'fmt '];tag,ech,erate,br,align,ewidth=struct.unpack_from('<HHIIHH',fmt)
    out=c['out'] or (100+c['width'] if c['floating'] else c['width'])
    assert (tag,ech,erate,align,ewidth)==(3 if out>100 else 1,ch,rate,ch*(out%100)//8,out%100)
    assert br==rate*align
    if tag==3:
        assert struct.unpack('<I',parts[b'fact'])[0]==frames
        expected=b''.join(struct.pack('<f' if ewidth==32 else '<d',v) for v in got)
    else:
        scale=1<<(ewidth-1)
        codes=[min(scale-1,max(-scale,round(max(-1.,min(1.,v))*scale))) for v in got]
        expected=b''.join(((v+128) if ewidth==8 else v%(1<<ewidth)).to_bytes(ewidth//8,'little') for v in codes)
        with wave.open(io.BytesIO(b),'rb') as w:
            assert (w.getnchannels(),w.getframerate(),w.getnframes(),w.getsampwidth())==(ch,rate,frames,ewidth//8)
            assert w.readframes(frames)==expected
    assert parts[b'data']==expected,(label,'encoded samples differ')
assert at==len(r.stdout),(at,len(r.stdout))
print('verified',len(cases),'WAVE cases, Python wave, exact PCM endpoints and 400k-frame workload')
