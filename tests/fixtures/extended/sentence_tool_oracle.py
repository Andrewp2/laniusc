"""Native sentence CLI: official frames, lossless CSV and syscall cleanup."""
from pathlib import Path
import csv
import io
import re
import runpy
import struct
import subprocess
import sys
import tempfile

exe=sys.argv[1];model=runpy.run_path('tests/fixtures/extended/unicode_sentences_oracle.py')
vectors=model['cases']()
def run(args,data):return subprocess.run([exe]+args,input=data,capture_output=True,timeout=15)
def spans(data,ends):
    start=0;result=[]
    for end in ends:result.append((start,end,data[start:end]));start=end
    return result

def frame_rows(data):
    at=0;result=[]
    while at<len(data):
        assert at+4<=len(data);n=struct.unpack_from('<I',data,at)[0];at+=4;assert n and at+n<=len(data)
        result.append(data[at:at+n]);at+=n
    assert at==len(data);return result
for text,ends in vectors[:512]:
    raw=text.encode();r=run(['--format','frames'],raw)
    assert r.returncode==0 and not r.stderr,(text,r.returncode,r.stderr)
    assert frame_rows(r.stdout)==[x[2] for x in spans(raw,ends)],(repr(text),r.stdout,ends)
for text in ['', 'Hi. A! 🙂.\n', '"Quoted.\n\" More?\t\0 End!\r\n', 'Mr. Jones. hello. 1.2! 終。次！', 'A.'+')'*20000+' '*20000+'lower']:
    raw=text.encode();ends=model['slow'](text) if len(text)<500 else [len(raw)]
    r=run([],raw);assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr)
    rows=list(csv.DictReader(io.StringIO(r.stdout.decode(),newline='')))
    expected=[dict(start=str(a),end=str(b),text=data.decode()) for a,b,data in spans(raw,ends)]
    assert rows==expected,(repr(text[:100]),rows[:5],expected[:5])
    r=run(['--format','frames'],raw);assert r.returncode==0 and frame_rows(r.stdout)==[x[2] for x in spans(raw,ends)]
raw=b'A! B.\n'
for args in [['operand'],['--format','bad'],['--format'],['--format','csv','--format','frames'],['--max-work','nan'],['--max-work','-1'],['--max-work','1000000001'],['--max-input-bytes','67108865'],['--max-output-bytes','67108865'],['--max-segments','16777217'],['--max-segments','1','--max-segments','2'],['--help','--format','csv'],['--wat']]:
    r=run(args,raw);assert r.returncode==2 and not r.stdout and b'invalid-arguments' in r.stderr,(args,r.returncode,r.stdout,r.stderr)
for bad,offset in [(b'\xff',0),(b'A! \xff',3),(b'\xc0\xaf',0),(b'\xe2\x82',0),(b'\xed\xa0\x80',0),(b'\xf4\x90\x80\x80',0)]:
    r=run([],bad);assert r.returncode==2 and not r.stdout and b'invalid-utf8' in r.stderr and ('byte='+str(offset)).encode() in r.stderr,(bad,r.returncode,r.stderr)
for args in [['--max-input-bytes','1'],['--max-output-bytes','15'],['--max-segments','1'],['--max-work',str(len(raw)*7-1)]]:
    r=run(args,raw);assert r.returncode==2 and not r.stdout and b'resource-limit' in r.stderr,(args,r.returncode,r.stdout,r.stderr)
r=run(['--max-work',str(len(raw)*7)],raw);assert r.returncode==0 and r.stdout
r=run(['--format','frames','--max-input-bytes','0','--max-output-bytes','0','--max-segments','0','--max-work','0'],b'');assert r.returncode==0 and not r.stdout and not r.stderr
r=run(['--max-input-bytes','0','--max-output-bytes','15','--max-segments','0','--max-work','0'],b'');assert r.returncode==0 and r.stdout==b'start,end,text\n'
r=run(['--help'],b'');assert r.returncode==0 and r.stdout.startswith(b'Usage: text-sentences ') and not r.stderr
# A multi-read, growing input exercises every allocation in the real consumer.
source=('He said "Hello!" Next.\r\n🙂! '*800).encode()
def traced(args,data,inject=None,output=None):
    with tempfile.NamedTemporaryFile() as trace:
        command=['strace','-qq','-o',trace.name,'-e','trace=mmap,munmap,read,write']
        if inject:command+=['-e',inject]
        command += [exe]+args
        r=subprocess.run(command,input=data,stdout=output or subprocess.PIPE,stderr=subprocess.PIPE,timeout=15)
        log=Path(trace.name).read_text()
    live={};allocs=0
    for line in log.splitlines():
        m=re.match(r'mmap\(NULL, (\d+),.*\) += (0x[0-9a-f]+)',line)
        if m:allocs+=1;assert m[2] not in live;live[m[2]]=int(m[1])
        m=re.match(r'munmap\((0x[0-9a-f]+), (\d+)\) += 0',line)
        if m:assert live.pop(m[1],None)==int(m[2]),line
    assert not live,('mapping leak',live,inject,log)
    return r,allocs,log
r,count,_=traced([],source);baseline=r.stdout;assert r.returncode==0 and count>=6,(r.returncode,count,r.stderr)
for nth in range(1,count+1):
    r,_,log=traced([],source,'inject=mmap:error=ENOMEM:when='+str(nth))
    assert r.returncode==4 and not r.stdout and b'allocation-failure' in r.stderr,(nth,r.returncode,r.stdout[:100],r.stderr,log)
for args,data in [(['--max-segments','1'],source),(['--max-output-bytes','15'],source),([],source+b'\xff')]:
    r,_,_=traced(args,data);assert r.returncode==2 and not r.stdout
for call in ['read','write']:
    r,_,_=traced([],source,'inject='+call+':error=EINTR:when=1')
    assert r.returncode==0 and r.stdout==baseline,(call,r.returncode,r.stderr)
    r,_,_=traced([],source,'inject='+call+':error=EIO:when=1')
    assert r.returncode==3 and not r.stdout and r.stderr,(call,r.returncode,r.stderr)
r,_,_=traced([],source,'inject=write:retval=1:when=1');assert r.returncode==0 and r.stdout==baseline[1:]
with open('/dev/full','wb') as full:
    r,_,_=traced([],source,output=full);assert r.returncode==3 and r.stderr
print('verified text-sentences512 official framed outputs, lossless CSV, UTF8/limits/arguments,',count,'allocation faults and I/O cleanup')
