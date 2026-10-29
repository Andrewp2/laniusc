"""Ordered byte-pair and full-wire reference, independent of Lanius cursors."""
from __future__ import annotations
from collections import Counter
from dataclasses import dataclass
import itertools
from pathlib import Path
import random
import re
import struct
import subprocess
import sys
from urllib.parse import quote_from_bytes, unquote_to_bytes

SEED=0xF04A0261112
MASK=(1<<64)-1
MAGIC=0x666F726D6D6F646C
END=0x656E64666F726D21
I32_MAX=(1<<31)-1
COUNTS=Counter()

def decode(data): return unquote_to_bytes(data.replace(b'+',b' '))
def encode(data):
    # CPython always leaves '~' literal, even when omitted from safe. Correct
    # that URI policy explicitly; form also admits '*' and uses '+' for space.
    return quote_from_bytes(data,safe='*-._').encode('ascii').replace(b'~',b'%7E').replace(b'%20',b'+')
def wire(pairs): return b'&'.join(encode(a)+b'='+encode(b) for a,b in pairs)
def fields(data):
    cuts=[]; offset=0
    for segment in data.split(b'&'):
        if segment:
            name,separator,value=segment.partition(b'=')
            value_start=offset+len(name)+(1 if separator else 0)
            cuts.append((offset,name,value_start,value))
        offset+=len(segment)+1
    return cuts
def parse(data,limits):
    incoming,pairs,component,total=limits
    if min(limits)<0:return 1,[]
    if len(data)>incoming:return 3,[]
    answer=[]; size=0
    for _,name,_,value in fields(data):
        if len(answer)>=pairs:return 4,[]
        a,b=decode(name),decode(value)
        if len(a)>component or len(b)>component:return 5,[]
        size+=len(a)+len(b)
        if size>total:return 6,[]
        answer.append((a,b))
    return 0,answer

@dataclass(frozen=True)
class Case:
    kind:int
    layout:int
    data:bytes
    limits:tuple=(4096,32,2048,4096)
    cap:int=16384
    cut:int=0

def append_body(operations):
    data=bytearray(struct.pack('<Q',len(operations)))
    for op,a,b in operations:data+=struct.pack('<3Q',op,len(a),len(b))+a+b
    return bytes(data)
def append_ops(body):
    count=struct.unpack_from('<Q',body)[0]; offset=8; result=[]
    for _ in range(count):
        op,n,m=struct.unpack_from('<3Q',body,offset);offset+=24
        result.append((op,body[offset:offset+n],body[offset+n:offset+n+m]));offset+=n+m
    assert offset==len(body);return result

def corpus():
    rng=random.Random(SEED); result=[]
    short=[bytes(chars) for n in range(4) for chars in itertools.product(b'&=+%a',repeat=n)]
    special=[b'a&a=&=v&=&a==b',b'a=1&a=2&z=3&a=4',b'&&a&&b&&',b'?a=b;c=d',
             b'_charset=ascii&x=%FF',b'a=%26%3D&%26=%3D',b'%2B+=%252B+%2b',
             b'bad=%GG%0%%%41%0G%G0',b'x=%00%7f%80%ff',b'*=~+*%20~',
             b'%EF%BB%BF=%EF%BB%BF',b'x=%C0%AF&x=%ED%A0%80&x=%F4%90%80%80',
             b'x=%F0%9F%98%80&%C3%A9=%E7%95%8C',b'x=%E2%82&y=ok',
             b'x=\r\n&y=\x00\xff&z=\xef\xbb\xbf',b'a=%2526%253D',
             b'a=%+1&b=%1+&c=%%&d=%',b'=&&==&&===',b'&',b'',b'=',
             b'\xff=\x80&\0=\0',b'x=%F0%90%80%80&x=%F4%8F%BF%BF']
    for _ in range(40):
        pieces=[]
        for _ in range(rng.randrange(1,14)):
            pair=[]
            for _ in range(2):
                raw=bytes(rng.randrange(256) for _ in range(rng.randrange(13)))
                pair.append(encode(raw) if rng.randrange(2) else raw.replace(b'&',b'%26'))
            pieces.append(pair[0]+rng.choice((b'=',b'=='))+pair[1])
        special.append(b'&'.join(pieces))
    for ordinal,data in enumerate(short+special):
        for layout in (0,1):result.append(Case(0,layout,data,cut=ordinal%7))
    # Admission edges and deterministic first-error precedence.
    for data in (b'',b'&&',b'=',b'a=1&a=2',b'a=%FF&b=xyz',b'%GG=+%2B'):
        decoded=[(decode(a),decode(b)) for _,a,_,b in fields(data)]
        n=len(decoded); c=max((len(x) for pair in decoded for x in pair),default=0)
        total=sum(len(a)+len(b) for a,b in decoded)
        variants=[(len(data),n,c,total),(len(data)-1,n,c,total),(len(data),n-1,c,total),
                  (len(data),n,c-1,total),(len(data),n,c,total-1),(-1,-1,-1,-1),
                  (0,0,0,0)]
        for limits in variants:
            for layout in (0,1):result.append(Case(0,layout,data,limits))
    # Exact output cap and every initial read cut for small diverse wires.
    for data in (b'a=%00+%FF',b'=&&x=%2B&x=~*',b'a=&a=1'):
        full=wire(parse(data,(4096,32,2048,4096))[1])
        for cut in range(len(full)+1):result.append(Case(0,cut%2,data,cap=len(full),cut=cut))
        result.append(Case(0,0,data,cap=max(0,len(full)-1)))
    components=[b'',bytes(range(256)),bytes(range(255,-1,-1)),b'* ~+%\0\xff',
                b''.join(('%%%02x%%%02X'%(x,x)).encode() for x in range(256)),
                b''.join(b'%'+bytes((x,))+b'0|' for x in range(256)),
                b''.join(b'%0'+bytes((x,))+b'|' for x in range(256)),
                b'%',b'%0',b'%GG',b'%%41',b'%2B+%252B',b'%EF%BB%BF',
                b'%C0%AF%ED%A0%80%F4%90%80%80',b'a'*1023+b'~ *%']
    for i,data in enumerate(components):
        for layout in (0,1):result.append(Case(1,layout,data,cut=i%13))
    base=[(0,b'',b''),(0,b'x',b'1'),(0,b'x',b'2'),(3,b'bad',b'x'),
          (0,b'toolong',b'0123456789'),(0,b'\xff',b'\0'),(1,b'',b''),
          (0,b'a',b''),(0,b'',b'b'),(0,b'',b''),(2,b'',b''),
          (0,b'* ~',b'%+'),(0,b'x',b'y'),(1,b'',b''),(0,b'',b'')]
    for limits in ((4096,0,0,0),(4096,1,0,0),(4096,3,4,8),(4096,8,32,64),
                   (4096,8,4,3),(4096,-1,4,8)):
        for layout in (0,1):result.append(Case(2,layout,append_body(base),limits,cap=7,cut=2))
    for _ in range(4):
        ops=[]
        for i in range(24):
            op=rng.choices((0,1,2,3),(16,2,1,1))[0]
            a=bytes(rng.choice(b'aa+%~*\xff\0') for _ in range(rng.randrange(6)))
            b=bytes(rng.randrange(256) for _ in range(rng.randrange(7)))
            ops.append((op,a,b))
        for layout in (0,1):result.append(Case(2,layout,append_body(ops),(4096,5,5,16),cap=16384,cut=3))
    assert all(len(c.data)<=2048 and c.cut<=31 for c in result)
    return result

class Writer:
    def __init__(self):self.data=bytearray();self.marks={}
    def mark(self,name):self.marks.setdefault(name,len(self.data))
    def byte(self,value):self.data.append(value)
    def word(self,value):self.data+=struct.pack('<Q',value&MASK)
    def blob(self,data,label=None):
        self.word(len(data))
        if label is not None and data:self.mark(label)
        self.data+=data
    def status(self,code,amount=0):self.word(code);self.word(amount)

def text_projection(w,data):
    try:data.decode('utf-8','strict')
    except UnicodeDecodeError as e:w.status(1,e.start);COUNTS['invalid_text']+=1
    else:w.status(0,0);w.blob(data,'text');COUNTS['valid_text']+=1
def pair(w,p):
    for x in p:w.blob(x,'pair bytes');text_projection(w,x)
def optional_pair(w,p):
    w.byte(p is not None)
    if p is not None:pair(w,p)
def owned_snapshot(w,pairs):
    COUNTS['snapshots']+=1;COUNTS['pairs_observed']+=len(pairs)
    w.word(len(pairs));w.word(sum(len(a)+len(b) for a,b in pairs))
    optional_pair(w,None)
    for p in pairs:optional_pair(w,p)
    optional_pair(w,None)
    for i,p in enumerate(pairs):w.word(len(pairs)-i);optional_pair(w,p)
    w.word(0);optional_pair(w,None);w.word(0);optional_pair(w,None)

def read_script(w,full,layout,cut):
    COUNTS['streams']+=1
    positions=[0,0];ordinal=0
    w.word(1 if layout else -8)
    def action(op,offset=0,count=0):
        nonlocal ordinal
        destination=bytearray((157+i*13+ordinal*7)&255 for i in range(64))
        w.byte(op)
        if op>=2:
            if op==2:positions[1]=positions[0]
            if op==3:positions[0]=positions[1]
            if op==4:positions[0]=0
            if op==5:positions[1]=0
            w.byte(2);w.word(0);COUNTS['copies']+=1;amount=0
        elif offset<0 or count<0 or count>I32_MAX-offset:
            w.byte(1);w.word(1);COUNTS['invalid_reads']+=1;amount=-1
        else:
            amount=min(count,len(full)-positions[op]);w.byte(0);w.word(amount)
            if amount:destination[offset:offset+amount]=full[positions[op]:positions[op]+amount]
            positions[op]+=amount;COUNTS['reads']+=1
            if count==0:COUNTS['zero_reads']+=1
            elif amount==0:COUNTS['eof_reads']+=1
        w.mark('remaining');w.word(len(full)-positions[0]);w.word(len(full)-positions[1])
        w.mark('destination');w.data+=destination;ordinal+=1;return amount
    for op,off,n in ((0,3,cut),(2,0,0),(0,7,1),(1,9,2),(0,I32_MAX,0),
                     (1,-1,0),(0,I32_MAX,1),(1,0,-1),(3,0,0),(5,0,0),(1,1,0),(0,2,3)):
        action(op,off,n)
    for cursor in (0,1):
        turn=0
        while True:
            got=action(cursor,3,(1,7,13,31)[turn%4]);turn+=1
            assert turn<=16384
            if got==0:break
        action(cursor,I32_MAX,0);action(cursor,-1,0);action(cursor,2,3)
    action(2);action(1,0,1)

def source_metadata(w,pairs,layout,raw=None):
    spans=[];offset=0
    if raw is None:
        backing=b''.join(a+b for a,b in pairs);origin=0;stride=1;span_start=0
        for a,b in pairs:spans.append((offset,len(a),len(b)));offset+=len(a)+len(b)
    else:
        backing=raw;origin=3;stride=1 if layout else -8;span_start=1
        n=len(raw);a=n//3;b=n//2
        spans=[(a,b-a,n-b),(0,a,b-a),(a,b-a,n-b),(n,0,0)]
    def view(start,data):w.word(start);w.word(stride);w.blob(data)
    w.mark('source metadata');w.byte(0);w.word(2);w.word(len(pairs))
    for (a,b),(start,_,_) in zip(pairs,spans):view(origin+start,a);view(origin+start+len(a),b)
    w.byte(1);view(origin,backing);w.word(span_start);w.word(len(spans))
    for span in spans:
        for x in span:w.word(x)

def serializations(w,pairs,layout,cap,cut,raw=None):
    source_metadata(w,pairs,layout,raw)
    full=wire(pairs);COUNTS['wire_bytes']+=len(full)
    w.mark('encoded length');w.status(0,len(full));w.status(0,len(full))
    code=9 if len(full)>cap else 0
    w.status(code,0 if code else len(full));w.status(code,0 if code else len(full))
    if not code:
        read_script(w,full,layout,cut)
        # Other representation emits its complete wire in fixed 31-byte reads.
        for start in range(0,len(full),31):w.blob(full[start:start+31],'wire')
        w.blob(b'')
    w.status(code,0 if code else len(full))
    if not code:w.data+=full
    COUNTS['output_rejections' if code else 'output_admissions']+=1
    source_metadata(w,pairs,layout,raw)

def borrowed_iteration(w,data):
    items=fields(data);positions=[0,0]
    def next_item(cursor):
        at=positions[cursor];positions[cursor]=min(at+1,len(items));w.byte(at<len(items))
        if at<len(items):
            ns,n,vs,v=items[at]
            for start,x in ((ns,n),(vs,v)):
                w.word(start+3);w.blob(x,'raw span')
    for op in (0,2,0,1,3,0,4,0,5,1):
        w.byte(op)
        if op<2:next_item(op)
        elif op==2:positions[1]=positions[0]
        elif op==3:positions[0]=positions[1]
        elif op==4:positions[0]=0
        else:positions[1]=0
    for cursor in (0,1):
        while positions[cursor]<len(items):w.byte(cursor);next_item(cursor)
        for _ in range(2):w.byte(cursor);next_item(cursor)

def component(w,data,layout):
    for transform in (encode,decode):
        expected=transform(data);w.status(0,len(expected))
        for capacity in (max(0,len(expected)-1),len(expected)):
            destination=bytearray((71+i*17)&255 for i in range(len(expected)+8))
            failed=capacity<len(expected)
            w.status(8 if failed else 0,len(expected))
            if not failed:destination[3:3+len(expected)]=expected
            w.mark('component destination');w.data+=destination
            COUNTS['component_calls']+=1

def expected(cases):
    COUNTS.clear();w=Writer();w.word(MAGIC);w.word(len(cases))
    for ordinal,c in enumerate(cases):
        w.word(ordinal);w.word(1 if c.layout else -8)
        if c.kind==0:
            code,pairs=parse(c.data,c.limits)
            w.status(code,len(pairs) if not code else 0)
            if not code:w.word(sum(len(a)+len(b) for a,b in pairs))
            w.status(code,len(pairs) if not code else 0)
            if not code:
                w.word(sum(len(a)+len(b) for a,b in pairs));borrowed_iteration(w,c.data)
                owned_snapshot(w,pairs);serializations(w,pairs,c.layout,c.cap,c.cut)
            COUNTS['parse_rejections' if code else 'parse_admissions']+=1
        elif c.kind==1:
            component(w,c.data,c.layout)
            # Packed spans share and reorder ranges, including empty slices.
            n=len(c.data);a=n//3;b=n//2
            pairs=[(c.data[a:b],c.data[b:]),(c.data[:a],c.data[a:b]),
                   (c.data[a:b],c.data[b:]),(b'',b'')]
            # The producer appends the selected pair values to an owner only
            # to compare owned serialization; its two borrowed sources use
            # the original shared/reordered packed ranges.
            owned_snapshot(w,pairs);serializations(w,pairs,c.layout,c.cap,c.cut,c.data)
        else:
            _,maximum,part,total=c.limits;code=1 if min(maximum,part,total)<0 else 0
            w.status(code)
            if not code:
                pairs=[]
                for op,a,b in append_ops(c.data):
                    w.byte(op);error=0
                    if op==3:error=2
                    elif op==0:
                        if len(pairs)>=maximum:error=4
                        elif len(a)>part or len(b)>part:error=5
                        elif sum(len(x)+len(y) for x,y in pairs)+len(a)+len(b)>total:error=6
                        else:pairs.append((a,b))
                    else:pairs=[]
                    w.status(error,len(pairs) if op==0 and not error else 0)
                    COUNTS['append_errors' if error else 'append_successes' if op==0 else 'clears' if op==1 else 'destroys']+=1
                    owned_snapshot(w,pairs);serializations(w,pairs,c.layout,c.cap,c.cut)
        backing=bytearray((193+i*19)&255 for i in range(2080))
        backing[3:3+len(c.data)]=c.data
        w.mark('source backing');w.data+=backing
    w.word(END)
    return bytes(w.data),w.marks,COUNTS.copy()

def packet(cases):
    output=bytearray(struct.pack('<2Q',MAGIC,len(cases)))
    for c in cases:output+=struct.pack('<9Q',c.kind,c.layout,len(c.data),*(x&MASK for x in c.limits),c.cap,c.cut)+c.data
    return bytes(output)
def summary(cases,counts):
    keys=('parse_admissions','parse_rejections','append_successes','append_errors','clears','destroys',
          'component_calls','streams','reads','copies','invalid_reads','pairs_observed')
    return 'form-model cases=%d '%len(cases)+' '.join('%s=%d'%(key,counts[key]) for key in keys)+' layouts=2 seed=0x%x\n'%SEED
def verify(actual,wanted):
    if actual!=wanted:
        at=next((i for i,(a,b) in enumerate(zip(actual,wanted)) if a!=b),min(len(actual),len(wanted)))
        raise AssertionError(('full output mismatch',at,len(actual),len(wanted),actual[at:at+24].hex(),wanted[at:at+24].hex()))
def controls(cases):
    wanted,marks,counts=expected(cases);verify(wanted,wanted)
    safe=set(b'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._')
    table=b''.join(bytes((x,)) if x in safe else b'+' if x==32 else ('%%%02X'%x).encode() for x in range(256))
    assert encode(bytes(range(256)))==table and decode(table)==bytes(range(256))
    assert decode(b'%2B+%252B')==b'+ %2B' and encode(b'* ~')==b'*+%7E'
    controls=[('truncated',wanted[:-1]),('trailing',wanted+b'\0')]
    for name,at in marks.items():
        bad=bytearray(wanted);bad[at]^=1;controls.append((name,bytes(bad)))
    for name,bad in controls:
        try:verify(bad,wanted)
        except AssertionError:pass
        else:raise AssertionError('accepted corruption: '+name)
    # Coherent semantic mutants, in addition to damaged protocol fields. These
    # regenerate full observations for a small reached witness, rather than
    # merely corrupting a byte whose meaning is unknown.
    witness=[Case(0,0,b'x=*+~&x=%2B+%252B&bad=%GG%&=&x=last'),
             Case(1,1,b'* ~+%2B%GG\xff')]
    baseline,_,_=expected(witness);original_encode=encode;original_decode=decode;original_parse=parse;original_fields=fields
    def collapsed(data,limits):
        code,pairs=original_parse(data,limits);return code,list(dict(pairs).items())
    mutants=[('literal tilde','encode',lambda x:original_encode(x).replace(b'%7E',b'~')),
             ('escaped asterisk','encode',lambda x:original_encode(x).replace(b'*',b'%2A')),
             ('lowercase escapes','encode',lambda x:re.sub(b'%[0-9A-F]{2}',lambda m:m[0].lower(),original_encode(x))),
             ('plus after decode','decode',lambda x:unquote_to_bytes(x).replace(b'+',b' ')),
             ('double decode','decode',lambda x:original_decode(original_decode(x))),
             ('percent loss','decode',lambda x:original_decode(x.replace(b'%',b''))),
             ('duplicate collapse','parse',collapsed),
             ('pair reordering','fields',lambda x:list(reversed(original_fields(x))))]
    for label,name,replacement in mutants:
        old=globals()[name]
        try:
            globals()[name]=replacement;bad,_,_=expected(witness)
        finally:globals()[name]=old
        try:verify(bad,baseline)
        except AssertionError:pass
        else:raise AssertionError('accepted semantic mutation: '+label)
    total=len(controls)+len(mutants)
    print(summary(cases,counts),end='');print('cpu-controls=%d rejected=%d bytes=%d'%(total,total,len(wanted)))
def main():
    cases=corpus()
    if len(sys.argv)==2 and sys.argv[1]=='controls':controls(cases);return
    assert len(sys.argv)==2
    wanted,_,counts=expected(cases)
    run=subprocess.run([str(Path(sys.argv[1]).resolve())],input=packet(cases),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=75,check=False)
    assert run.returncode==0,('native status',run.returncode,run.stderr[:2048])
    assert not run.stderr,('native stderr',run.stderr[:2048])
    verify(run.stdout,wanted);print(summary(cases,counts),end='')
if __name__=='__main__':main()
