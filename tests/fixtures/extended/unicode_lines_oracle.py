"""Complete official Unicode 17 corpus; expected decisions are not generated."""
import gzip, pathlib, struct, subprocess, sys, tempfile
root=pathlib.Path(sys.argv[2]); cases=[]
source=gzip.decompress((root/'data/unicode/17.0.0/unicode-lines-LineBreakTest.txt.gz').read_bytes()).decode()
assert source.startswith('# LineBreakTest-17.0.0.txt')
for line in source.splitlines():
    body=line.split('#')[0].strip()
    if not body:continue
    text='';ends=[]
    for token in body.split():
        if token=='÷': ends.append(len(text.encode()))
        elif token!='×':text+=chr(int(token,16))
    cases.append((text,ends,line))
assert len(cases)==19338
extras=[('',[0]), ('\r\n\n\r\x0b\x0c\x85\u2028\u2029',[2,3,4,5,6,8,11,14])]
for prefix in ['(','“']:
    text=prefix+' '*16000+'x';extras.append((text,[len(text.encode())]))
marks='\u0308'*12000
for text in ['$('+marks+'.'+marks+'5)', 'ᬅ'+('᭄'+marks+'ᬅ')*2, '1'+',.'*12000+'$X']:
    extras.append((text,[len(text.encode())]))
text=('🇦\u0308')*8193; unit=len('🇦\u0308'.encode());extras.append((text,list(range(unit*2,len(text.encode()),unit*2))+[len(text.encode())]))
for text,ends in extras:cases.append((text,ends,'long/degenerate context'))
payload=b''.join(struct.pack('<I',len(text.encode()))+text.encode() for text,_,_ in cases)
with tempfile.TemporaryDirectory() as folder:
    trace=pathlib.Path(folder)/'allocations'
    command=['strace','-qq','-o',str(trace),'-e','trace=mmap,munmap','-e','inject=mmap:error=ENOMEM:when=1+',sys.argv[1]]
    result=subprocess.run(command,input=payload,capture_output=True,timeout=40)
    assert trace.read_text()=='','line cursor attempted to allocate'
assert result.returncode==0 and not result.stderr,(result.returncode,result.stderr)
lines=result.stdout.decode().splitlines();assert len(lines)==len(cases),(len(lines),len(cases))
fail=[]
for index,((text,want,origin),line) in enumerate(zip(cases,lines)):
    encoded=[int(x) for x in line.split(',') if x];got=[-x-1 if x<0 else x for x in encoded]
    if got!=want:fail.append((index,repr(text[:80]),want,got,origin))
    else:
        at=0;hard={}
        for char in text:at+=len(char.encode());hard[at]=char in '\r\n\x0b\x0c\x85\u2028\u2029'
        for value,offset in zip(encoded,got):assert (value<0)==(offset==len(text.encode()) or hard.get(offset,False)),(index,offset,value)
if fail:
    for item in fail[:25]:print(item)
    raise AssertionError(f'{len(fail)} failures of {len(cases)}')
print('Unicode 17 full line-break conformance: 19338 official cases +',len(extras),'long/degenerate contexts')
