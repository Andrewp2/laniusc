"""Unicode 17 official vectors and a slow declarative SB-rule oracle."""
from pathlib import Path
import gzip
import hashlib
import json
import random
import re
import struct
import subprocess
import sys
import tempfile

ROOT=Path('data/unicode/17.0.0')
IDS=dict(Other='x',CR='c',LF='f',Extend='e',Format='q',Sep='p',Sp='s',Lower='l',Upper='u',OLetter='o',Numeric='n',ATerm='a',STerm='t',Close='k',SContinue='v')
def checked(name):
    manifest=json.loads((ROOT/'sentences-manifest.json').read_text())
    entry=next(e for e in manifest['files'] if e['file']=='sentences-'+name+'.txt.gz')
    packed=(ROOT/entry['file']).read_bytes();raw=gzip.decompress(packed)
    assert hashlib.sha256(packed).hexdigest()==entry['gzip_sha256']
    assert hashlib.sha256(raw).hexdigest()==entry['sha256'] and len(raw)==entry['bytes']
    return raw.decode()
properties=bytearray(b'x'*0x110000);ranges=[];examples={}
for line in checked('SentenceBreakProperty').splitlines():
    body=line.split('#')[0].strip()
    if not body:continue
    span,name=map(str.strip,body.split(';'));bounds=span.split('..');first,last=int(bounds[0],16),int(bounds[-1],16)
    prop=IDS[name];assert all(x==ord('x') for x in properties[first:last+1]);properties[first:last+1]=bytes([ord(prop)])*(last-first+1)
    ranges.append((first,last));examples.setdefault(prop,[]).append(first)
examples['x']=[0,0x10ffff,0x1f642]

def slow(text):
    raw=''.join(chr(properties[ord(c)]) for c in text)
    left='';ends=[];offset=0
    for i,(char,current) in enumerate(zip(text,raw)):
        if i:
            previous=raw[i-1]
            if previous=='c' and current=='f':boundary=False # SB3
            elif previous in 'cfp':boundary=True # SB4
            elif current in 'eq':boundary=False # SB5
            elif left.endswith('a') and current=='n':boundary=False # SB6
            elif re.search('[ul]a$',left) and current=='u':boundary=False # SB7
            elif re.search('ak*s*$',left) and re.match('[^oulpcfat]*l',raw[i:]):boundary=False # SB8
            elif re.search('[at]k*s*$',left) and current in 'vat':boundary=False # SB8a
            elif re.search('[at]k*$',left) and current in 'kscfp':boundary=False # SB9
            elif re.search('[at]k*s*$',left) and current in 'scfp':boundary=False # SB10
            elif re.search('[at]k*s*[cfp]?$',left):boundary=True # SB11
            else:boundary=False # SB998
            if boundary:ends.append(offset)
        # Ignore expansion after sot/paragraph retains a real Other scalar;
        # later ignored scalars disappear only from post-SB5 left contexts.
        if current not in 'eq':left+=current
        elif i==0 or raw[i-1] in 'cfp':left+='x'
        offset+=len(char.encode())
    if text:ends.append(offset)
    return ends

def cases():
    result=[]
    for line in checked('SentenceBreakTest').splitlines():
        body=line.split('#')[0].strip()
        if not body:continue
        text='';ends=[]
        for token in body.split():
            if token=='÷':
                if text:ends.append(len(text.encode()))
            elif token!='×':text+=chr(int(token,16))
        assert slow(text)==ends,('slow oracle vs official',line,slow(text),ends)
        result.append((text,ends))
    assert len(result)==512,'the complete official corpus must execute'
    rng=random.Random(0x29_17_5)
    for _ in range(2500):
        text=''.join(chr(rng.choice(examples[rng.choice(list(examples))])) for _ in range(rng.randrange(1,35)))
        result.append((text,slow(text)))
    # Range endpoints and their neighbors, under sentence-sensitive contexts,
    # exercise the generated lookup independently of its encoded range layout.
    points={0,0x10ffff,0x10fffe,0x0378,0xe000,0x1fc00}
    for first,last in ranges:
        points.update(p for p in [first-1,first,last,last+1] if 0<=p<=0x10ffff and not 0xd800<=p<=0xdfff)
    for p in sorted(points):
        text='a.'+chr(p)+'Z! a';result.append((text,slow(text)))
    for text in ['', '\r\u0308\nA', 'Mr. Jones. Hi!', 'a.A. 1.2! More?', '終。次！', '\0! A', '\u0308\u200eA. x', '. ) lower', 'A. \u200e\u0308\nB']:
        result.append((text,slow(text)))
    for end in ['lower','Upper']:
        text='A.'+')'*24000+' '*24000+end
        result.append((text,[len(text.encode())] if end=='lower' else [len(text)-len(end),len(text)]))
        text='A. '+'0,\u0308\u200e'*6000+end
        result.append((text,[len(text.encode())] if end=='lower' else [3,len(text.encode())]))
    text=('A.'+')'*100+' '*100+'1lower ')*256
    result.append((text,[len(text)]))
    text=('A.'+')'*100+' '*100+'Upper ')*256
    result.append((text,[i*208+202 for i in range(256)]+[len(text)]))
    text='A.'+'\u0308\u200e'*18000+'B'
    # SB7 ignores all marks between ATerm and Upper.
    result.append((text,[len(text.encode())]))
    return result

def run(executable):
    vectors=cases();packet=b''.join(struct.pack('<I',len(s.encode()))+s.encode() for s,e in vectors)
    assert max(len(s.encode()) for s,e in vectors)<=131072
    with tempfile.NamedTemporaryFile() as trace:
        r=subprocess.run(['strace','-qq','-o',trace.name,'-e','trace=mmap,munmap','-e','inject=mmap:error=ENOMEM:when=1+',executable],input=packet,capture_output=True,timeout=45)
        events=Path(trace.name).read_text()
    assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr)
    assert not events,('segmentation attempted allocation',events)
    lines=r.stdout.decode().splitlines();assert len(lines)==len(vectors),(len(lines),len(vectors))
    for i,((text,expected),line) in enumerate(zip(vectors,lines)):
        actual=[int(s) for s in line.split(',') if s]
        assert actual==expected,('seed=0x29175',i,repr(text[:100]),actual[:100],expected[:100])
    print('verified',len(vectors),'sentence cases: all512 Unicode17 vectors, slow declarative oracle, range endpoints, seeded contexts and linear-lookahead scale; zero allocations')

if __name__=='__main__':run(sys.argv[1])
