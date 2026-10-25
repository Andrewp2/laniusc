"""Independent fitting model over explicit clusters and known opportunities.

Default break decisions themselves are checked separately by the complete UCD
corpus. Widths here are explicit policy vectors, not calls into production.
"""
import os, random, subprocess, sys, tempfile
exe=sys.argv[1];rng=random.Random(0x170014)
def atom(s,g=1,scalar=None,wide=None):return (s,g,g if scalar is None else scalar,g if wide is None else wide)
words=[([atom(c) for c in 'hello'],set()),([atom('a\u0301'),atom('b'),atom('c')],set()),([atom(c,2) for c in '一二三'],{1,2}),([atom('👩\u200d💻',2,4)],set()),([atom('🇦🇧',2)],set()),([atom('❤️',2,1)],set()),([atom('1️⃣',2,1)],set()),([atom('·',1,1,2)],set())]
def paragraph(sequence):
    clusters=[];allowed=set()
    for i,(items,internal) in enumerate(sequence):
        base=len(clusters);clusters+=items;allowed|={base+j for j in internal}
        if i+1<len(sequence):clusters.append(atom(' '));allowed.add(len(clusters))
    allowed.add(len(clusters));return clusters,allowed
def model(paragraphs,columns,scalar=False,ambiguous=False,reject=False):
    output=''
    for clusters,allowed,separator in paragraphs:
        prefix=[0]
        for s,g,sc,wide in clusters:prefix.append(prefix[-1]+(wide if ambiguous and wide!=g else sc if scalar else g))
        start=0
        while start<len(clusters):
            candidates=sorted(j for j in allowed if j>start);fits=[j for j in candidates if prefix[j]-prefix[start]<=columns]
            end=max(fits) if fits else min(candidates)
            if reject and prefix[end]-prefix[start]>columns:return None
            output+=''.join(c[0] for c in clusters[start:end]);start=end
            if start<len(clusters):output+='\n'
        if separator:output+='\n'
    return output.encode()
def run(data,args=()):return subprocess.run([exe,*args],input=data,capture_output=True,timeout=10)
cases=[]
for _ in range(110):
    sequence=[rng.choice(words) for _ in range(rng.randrange(0,10))];clusters,allowed=paragraph(sequence);cases.append(([(clusters,allowed,'')],rng.randrange(1,18),rng.choice([False,True]),rng.choice([False,True]),rng.choice([False,True])))
for separator in ['\n','\r','\r\n','\x0b','\x0c','\x85','\u2028','\u2029']:
    one=paragraph([words[0],words[2]]);two=paragraph([words[3],words[5]])
    cases.append(([(one[0],one[1],separator),([], {0},separator),(two[0],two[1],separator)],5,False,False,False))
for clusters,allowed in [([atom('a'),atom(' \u0301'),atom('b')],{3}),([atom('a'),atom('b'),atom('\u200b',0),atom('c'),atom('d')],{3,5}),([atom('a'),atom('b'),atom('\u2060',0),atom('c'),atom('d')],{5}),([atom('a'),atom('\u00a0'),atom('b')],{3}),([atom('a'),atom('b'),atom('\u00ad',0),atom('c'),atom('d')],{3,5})]:
    for columns in [1,2,3,8]:cases.append(([(clusters,allowed,'')],columns,False,False,False))
for index,(paragraphs,columns,scalar,ambiguous,reject) in enumerate(cases):
    source=''.join(''.join(c[0] for c in clusters)+separator for clusters,_,separator in paragraphs).encode()
    args=['--columns',str(columns)]+(['--scalar-width'] if scalar else [])+(['--ambiguous-wide'] if ambiguous else [])+(['--overlong','error'] if reject else [])
    want=model(paragraphs,columns,scalar,ambiguous,reject);r=run(source,args)
    if want is None:assert r.returncode==2 and not r.stdout and r.stderr==b'text-wrap: invalid input or resource limit\n',(index,r)
    else:assert r.returncode==0 and r.stdout==want and not r.stderr,(index,source,args,r.returncode,r.stdout,want,r.stderr)
# Exact policy limits, including no unwanted EOT newline and empty output.
for source,args,want in [(b'',['--max-input-bytes','0','--max-scalars','0','--max-output-bytes','0','--max-lines','0','--max-work','1'],b''),(b'ab cd ef',['--columns','3','--max-input-bytes','8','--max-scalars','8','--max-output-bytes','10','--max-lines','3','--max-work','513'],b'ab \ncd \nef')]:
    r=run(source,args);assert r.returncode==0 and r.stdout==want and not r.stderr,(r,args)
source=b'ab cd ef'
for flag,value in [('--max-input-bytes','7'),('--max-scalars','7'),('--max-output-bytes','9'),('--max-lines','2'),('--max-work','512')]:
    r=run(source,['--columns','3',flag,value]);assert r.returncode==2 and not r.stdout,(flag,r)
for source,args in [(b'abc\xff',[]),(b'\xc0\xaf',[]),(b'\xed\xa0\x80',[]),(b'a\tb',[]),(b'a\0b',[]),(b'a\x1b[31mb',[]),('a\u202eb'.encode(),[]),(b'x',['--columns','0']),(b'x',['--columns','2','--columns','3']),(b'x',['--overlong','bogus']),(b'x',['operand']),(b'x',['--help','--scalar-width'])]:
    r=run(source,args);assert r.returncode==2 and not r.stdout and r.stderr==b'text-wrap: invalid input or resource limit\n',(source,args,r.returncode,r.stderr)
help=run(b'',['--help']);assert help.returncode==0 and help.stdout.endswith(b'\n') and b'--max-work N]' in help.stdout and not help.stderr
source=b'a '*20000;r=run(source,['--columns','2']);assert r.returncode==0 and r.stdout==b'a \n'*19999+b'a ' and not r.stderr
def ledger(trace):
    live=set();count=0
    for line in trace.splitlines():
        if line.startswith('mmap(') and '= -1' not in line:
            address=line.rsplit(' = ',1)[1].split()[0];assert address not in live;live.add(address);count+=1
        elif line.startswith('munmap('):
            address=line[7:].split(',')[0];assert line.endswith(' = 0') and address in live,(line,trace);live.remove(address)
    assert not live,(live,trace);return count
with tempfile.TemporaryDirectory() as folder:
    trace=os.path.join(folder,'trace');source=b'a '*256
    def traced(fault=None,data=source,args=['--columns','2']):
        command=['strace','-qq','-o',trace,'-e','trace=mmap,munmap,read,write']
        if fault:command+=['-e',fault]
        r=subprocess.run(command+[exe,*args],input=data,capture_output=True,timeout=10);events=open(trace).read();return r,ledger(events),events
    baseline,count,_=traced();assert baseline.returncode==0 and count>=8,(baseline,count)
    for when in range(1,count+1):
        r,_,events=traced(f'inject=mmap:error=ENOMEM:when={when}+')
        assert r.returncode==4 and not r.stdout and r.stderr==b'text-wrap: allocation failed\n',(when,r.returncode,r.stdout,r.stderr);assert 'INJECTED' in events
    for fault in ['inject=read:error=EIO:when=1','inject=write:error=EIO:when=1']:
        r,_,events=traced(fault);assert r.returncode==3,(fault,r.returncode,r.stderr);assert 'INJECTED' in events
    for fault in ['inject=read:error=EINTR:when=1','inject=write:error=EINTR:when=1']:
        r,_,_=traced(fault);assert r.returncode==0 and r.stdout==baseline.stdout and r.stderr==baseline.stderr,(fault,r.returncode,r.stderr)
    for data,args in [(source+b'\x1b', ['--columns','2']),(source,['--columns','2','--max-lines','10']),(source,['--columns','2','--max-output-bytes','10'])]:
        r,_,_=traced(data=data,args=args);assert r.returncode==2 and not r.stdout
    r,_,_=traced('inject=write:error=EIO:when=1+',data=b'\x1b');assert r.returncode==3 and not r.stdout and not r.stderr
print('text-wrap independent width/fitting cases',len(cases),'plus scale, exact limits, all allocator denials, cleanup and I/O faults')
