import csv,fractions,io,math,os,random,re,struct,subprocess,sys,tempfile,wave
exe=sys.argv[1];rng=random.Random(0x7a001026)
def wav(width,ch,values):
    buf=io.BytesIO()
    with wave.open(buf,'wb') as w:
        w.setnchannels(ch);w.setsampwidth(width//8);w.setframerate(44100)
        w.writeframes(b''.join(((v+128) if width==8 else v%(1<<width)).to_bytes(width//8,'little') for v in values))
    return buf.getvalue()
def run(args,data):return subprocess.run([exe]+args,input=data,capture_output=True,timeout=15)
for width in [8,16,24,32]:
    scale=1<<(width-1)
    x=[rng.randrange(-scale,scale) for _ in range(900)]
    src=wav(width,3,x)
    for out in [8,16,24,32]:
        r=run(['--gain','0.5','--mono','--pcm-bits',str(out)],src)
        assert r.returncode==0 and not r.stderr,(width,out,r.returncode,r.stderr)
        with wave.open(io.BytesIO(r.stdout),'rb') as w:
            assert (w.getnchannels(),w.getframerate(),w.getnframes(),w.getsampwidth())==(1,44100,300,out//8)
            raw=w.readframes(300)
            scale_out=1<<(out-1)
            means=[math.fsum(x[i:i+3])/scale/6 for i in range(0,len(x),3)]
            want=[min(scale_out-1,max(-scale_out,round(v*scale_out))) for v in means]
            got=[int.from_bytes(raw[i:i+out//8],'little',signed=out!=8)-(128 if out==8 else 0) for i in range(0,len(raw),out//8)]
            assert got==want,(width,out,got[:10],want[:10])
    r=run(['--stats'],src);assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr)
    rows=list(csv.DictReader(io.StringIO(r.stdout.decode())))
    assert len(rows)==3
    for ch,row in enumerate(rows):
        a=[v/scale for v in x[ch::3]]
        assert (int(row['channel']),int(row['frames']),int(row['sample_rate']))==(ch,300,44100)
        for key,expected in [('peak',max(map(abs,a))),('rms',math.sqrt(math.fsum(v*v for v in a)/len(a))),('dc',math.fsum(a)/len(a))]:
            assert abs(float(row[key])-expected)<1e-14,(width,ch,key,row[key],expected)
# The real consumer must retain cancellation residuals through both modes.
def floating_wave(ch,values):
    frames=len(values)//ch
    def chunk(tag,data):return tag+struct.pack('<I',len(data))+data
    fmt=struct.pack('<HHIIHHH',3,ch,44100,44100*ch*8,ch*8,64,0)
    body=b'WAVE'+chunk(b'fmt ',fmt)+chunk(b'fact',struct.pack('<I',frames))+chunk(b'data',struct.pack('<'+'d'*len(values),*values))
    return b'RIFF'+struct.pack('<I',len(body))+body
values=[sys.float_info.max,1e-300,-sys.float_info.max]
expected=float(sum(map(fractions.Fraction.from_float,values),fractions.Fraction(0))/3)
r=run(['--mono'],floating_wave(3,values));assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr)
assert struct.unpack_from('<HH',r.stdout,20)==(3,1)
assert struct.unpack_from('<d',r.stdout,58)[0]==expected,(r.stdout,expected)
r=run(['--stats'],floating_wave(1,values));assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr)
rows=list(csv.DictReader(io.StringIO(r.stdout.decode())));assert len(rows)==1 and float(rows[0]['dc'])==expected,(rows,expected)
src=wav(16,2,[-32768,32767,0,16384]*3000)
for args in [['--gain','nan'],['--gain','inf'],['--gain','1e999'],['--gain','x'],['--gain','9'*100],['--gain','1','--gain','2'],['--pcm-bits','12'],['--stats','--pcm-bits','16'],['operand'],['--help','--stats'],['--max-input-bytes','1'],['--max-samples','2'],['--max-output-bytes','1'],['--gain'],['--mono','--mono']]:
    r=run(args,src);assert r.returncode==2 and not r.stdout and r.stderr,(args,r.returncode,r.stdout[:20],r.stderr)
for data in [b'',b'no wave',src[:-1],src+b'x']:
    r=run([],data);assert r.returncode==2 and not r.stdout and r.stderr,(r.returncode,r.stderr)
r=run(['--help'],b'');assert r.returncode==0 and r.stdout.startswith(b'Usage: wave-tool ') and not r.stderr
r=run([],src);assert r.returncode==0 and r.stdout==src,(r.returncode,r.stderr)
# Independent syscall ledger: every mapping made by the native artifact must
# be unmapped by the program before exit, including failures during staging.
def traced(args,data,inject=None,output=None):
    with tempfile.NamedTemporaryFile() as trace:
        command=['strace','-qq','-o',trace.name,'-e','trace=mmap,munmap,read,write']
        if inject:command += ['-e',inject]
        command += [exe]+args
        r=subprocess.run(command,input=data,stdout=output or subprocess.PIPE,stderr=subprocess.PIPE,timeout=15)
        log=open(trace.name).read()
    live={};allocs=0
    for line in log.splitlines():
        m=re.match(r'mmap\(NULL, (\d+),.*\) += (0x[0-9a-f]+)',line)
        if m:allocs+=1;assert m[2] not in live;live[m[2]]=int(m[1])
        m=re.match(r'munmap\((0x[0-9a-f]+), (\d+)\) += 0',line)
        if m:assert live.pop(m[1],None)==int(m[2]),line
    assert not live,('leaked mappings',live,inject,log)
    return r,allocs,log
r,count,_=traced(['--gain','0.5','--mono','--pcm-bits','24'],src)
assert r.returncode==0 and count>=5,(r.returncode,count,r.stderr)
for nth in range(1,count+1):
    r,_,log=traced(['--gain','0.5','--mono','--pcm-bits','24'],src,'inject=mmap:error=ENOMEM:when='+str(nth))
    assert r.returncode==4 and not r.stdout and r.stderr,(nth,r.returncode,r.stdout[:20],r.stderr,log)
for call in ['read','write']:
    r,_,_=traced([],src,'inject='+call+':error=EINTR:when=1')
    assert r.returncode==0 and r.stdout==src,(call,r.returncode,r.stderr)
    r,_,_=traced([],src,'inject='+call+':error=EIO:when=1')
    assert r.returncode==3 and not r.stdout and r.stderr,(call,r.returncode,r.stderr)
# Positive short write accounting: strace skips the first byte, then the
# program must continue from byte one and terminate successfully.
r,_,_=traced([],src,'inject=write:retval=1:when=1')
assert r.returncode==0 and r.stdout==src[1:],(r.returncode,len(r.stdout),len(src),r.stderr)
with open('/dev/full','wb') as full:
    r,_,_=traced([],src,output=full);assert r.returncode==3 and r.stderr
print('verified wave-tool transforms, CSV metrics, argument limits,',count,'allocation faults, I/O faults and mapping cleanup')
