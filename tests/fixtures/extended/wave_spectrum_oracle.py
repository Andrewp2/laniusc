import cmath, csv, fractions, io, math, os, struct, subprocess, sys, tempfile
F=fractions.Fraction
exe=sys.argv[1]
def chunk(tag,payload):return tag+struct.pack('<I',len(payload))+payload+(b'\0' if len(payload)%2 else b'')
def wave(frames,rate=8000):
    channels=len(frames[0]) if frames else 1
    fmt=struct.pack('<HHIIHHH',3,channels,rate,rate*channels*8,channels*8,64,0)
    payload=b''.join(struct.pack('<d',value) for frame in frames for value in frame)
    body=b'WAVE'+chunk(b'fmt ',fmt)+chunk(b'fact',struct.pack('<I',len(frames)))+chunk(b'data',payload)
    return b'RIFF'+struct.pack('<I',len(body))+body

def run(data,args=(),**kw):return subprocess.run([exe,*args],input=data,capture_output=True,timeout=12,**kw)
def expected(frames,kind='hann',periodic=True,smooth=1,size=None):
    samples=[float(sum(map(F.from_float,frame),F(0))/len(frame)) for frame in frames]
    if smooth>1:
        coefficients=[1./smooth]*smooth
        samples=[math.fsum(samples[j]*coefficients[i-j] for j in range(len(samples)) if 0<=i-j<smooth) for i in range(len(samples)+smooth-1)]
    n=len(samples);size=size or (1<<(n-1).bit_length())
    for i,x in enumerate(samples):
        a=0 if n==1 else math.tau*i/(n if periodic else n-1)
        coefficient=1 if kind=='rect' or n==1 else .5-.5*math.cos(a) if kind=='hann' else .54-.46*math.cos(a) if kind=='hamming' else .42-.5*math.cos(a)+.08*math.cos(2*a)
        samples[i]=x*max(0.,min(1.,coefficient))
    values=samples+[0.]*(size-n);out=[]
    for k in range(size//2+1):
        terms=[x*cmath.exp(-1j*math.tau*i*k/size) for i,x in enumerate(values)]
        value=complex(math.fsum(v.real for v in terms),math.fsum(v.imag for v in terms))/size
        out.append((k,8000*k/size,abs(value),value.real*value.real+value.imag*value.imag))
    return out
frames=[[.8*math.cos(math.tau*3*i/32),.4*math.cos(math.tau*3*i/32)] for i in range(32)]
cases=[(frames,[],{}), (frames,['--window','rect'],dict(kind='rect')), (frames,['--window','hamming','--symmetric'],dict(kind='hamming',periodic=False)), (frames,['--window','blackman','--fft-size','64'],dict(kind='blackman',size=64)), (frames,['--smooth','3','--window','rect'],dict(smooth=3,kind='rect')), ([[.75]],['--window','hann'],{}), ([[1.],[0.],[0.],[0.]],['--window','rect'],dict(kind='rect'))]
for index,(frames,args,options) in enumerate(cases):
    r=run(wave(frames),args);assert r.returncode==0 and not r.stderr,(index,r.returncode,r.stderr)
    rows=list(csv.reader(io.StringIO(r.stdout.decode())))
    assert rows[0]==['bin','frequency_hz','magnitude','power'],(index,rows[:1])
    want=expected(frames,**options);assert len(rows)==len(want)+1,(index,len(rows),len(want))
    for row,reference in zip(rows[1:],want):
        got=list(map(float,row));assert got[0]==reference[0]
        for j,(a,b) in enumerate(zip(got[1:],reference[1:])):assert math.isfinite(a) and abs(a-b)<=2e-11*max(1.,abs(b)),(index,j,a,b)
source=wave([[.25,-.5],[.75,.5],[0.,1.],[.5,0.]])
for data,args in [(b'',[]),(source[:-1],[]),(wave([]),[]),(source,['--fft-size','2']),(source,['--fft-size','3']),(source,['--smooth','0']),(source,['--window','bogus']),(source,['--window','hann','--window','rect']),(source,['--max-input-bytes','1']),(source,['--max-samples','1']),(source,['--max-output-bytes','1']),(source,['--max-work','1']),(source,['operand']),(source,['--help','--symmetric']),(wave([[math.nan]]),[]),(wave([[sys.float_info.max],[sys.float_info.max]]),['--window','rect'])]:
    r=run(data,args);assert r.returncode==2 and not r.stdout and r.stderr==b'wave-spectrum: invalid input or resource limit\n',(args,r.returncode,r.stdout,r.stderr)
help=run(b'', ['--help']);assert help.returncode==0 and b'Usage: wave-spectrum' in help.stdout and not help.stderr

def ledger(trace):
    live=set();count=0
    for line in trace.splitlines():
        if line.startswith('mmap(') and '= -1' not in line:
            address=line.rsplit(' = ',1)[1].split()[0];assert address not in live;live.add(address);count+=1
        elif line.startswith('munmap('):
            address=line[7:].split(',')[0];assert line.endswith(' = 0') and address in live,(line,trace);live.remove(address)
    assert not live,(live,trace)
    return count
with tempfile.TemporaryDirectory() as folder:
    trace=os.path.join(folder,'trace')
    def traced(fault=None):
        command=['strace','-qq','-o',trace,'-e','trace=mmap,munmap,read,write']
        if fault:command+=['-e',fault]
        r=subprocess.run(command+[exe,'--smooth','3','--window','blackman'],input=source,capture_output=True,timeout=10)
        events=open(trace).read();count=ledger(events);return r,count,events
    baseline,count,_=traced();assert baseline.returncode==0,(baseline.returncode,baseline.stderr);assert count>=9,count
    for when in range(1,count+1):
        r,_,events=traced(f'inject=mmap:error=ENOMEM:when={when}+')
        assert r.returncode==4 and not r.stdout and r.stderr==b'wave-spectrum: allocation failed\n',(when,r.returncode,r.stdout,r.stderr)
        assert 'INJECTED' in events
    for fault in ['inject=read:error=EIO:when=1','inject=write:error=EIO:when=1']:
        r,_,events=traced(fault);assert r.returncode==3,(fault,r.returncode,r.stderr);assert 'INJECTED' in events
    for fault in ['inject=read:error=EINTR:when=1','inject=write:error=EINTR:when=1']:
        r,_,_=traced(fault);assert r.returncode==0 and r.stdout==baseline.stdout and r.stderr==baseline.stderr,(fault,r.returncode,r.stderr)
print('wave-spectrum independent DFT/CSV/filter and allocation/I/O fault contracts verified')
