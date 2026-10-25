# CPU-only identity oracle. No production implementation or DNS lookup.
import ipaddress
import pathlib
import random
import re
import struct
import subprocess
import sys
import tempfile

ANY = 2**64-1
def tlv(tag,body):
    n=len(body);w=max(1,(n.bit_length()+7)//8)
    return bytes([tag])+(bytes([n]) if n<128 else bytes([128+w])+n.to_bytes(w,'big'))+body
def seq(*values):return tlv(48,b''.join(values))
AI=bytes.fromhex('300506032b6570')
KEY=bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')
def name(cn):return seq(tlv(49,seq(bytes.fromhex('0603550403'),tlv(12,cn))))
def certificate(names=None,cn=b'api.example.test'):
    extension=b'' if names is None else tlv(163,seq(seq(bytes.fromhex('0603551d11'),tlv(4,seq(*(tlv(tag,value) for tag,value in names))))))
    tbs=seq(tlv(160,bytes.fromhex('020102')),bytes.fromhex('020101'),AI,name(b'Identity test CA'),seq(tlv(23,b'261024000000Z'),tlv(23,b'491024000000Z')),name(cn),seq(AI,tlv(3,b'\0'+KEY)),extension)
    return seq(tbs,AI,tlv(3,bytes(65))) # Schema fixture, not an authenticated signature.
def nodes(data,origin=0):
    result=[];at=0
    while at<len(data):
        start=at;tag=data[at];n=data[at+1];at+=2
        if n&128:w=n&127;n=int.from_bytes(data[at:at+w],'big');at+=w
        end=at+n;assert end<=len(data);result.append((tag,data[at:end],origin+at,origin+start));at=end
    assert at==len(data);return result
def sans(cert):
    outer=nodes(cert)[0];fields=nodes(outer[1],outer[2]);tbs=fields[0];parts=nodes(tbs[1],tbs[2]);result=[]
    for tag,body,offset,_ in parts:
        if tag!=163:continue
        exts=nodes(body,offset)[0]
        for _,body,offset,_ in nodes(exts[1],exts[2]):
            ext=nodes(body,offset)
            if ext[0][1]!=bytes.fromhex('551d11'):continue
            names=nodes(ext[-1][1],ext[-1][2])[0]
            result.extend((tag,value,offset) for tag,value,offset,_ in nodes(names[1],names[2]))
    return result

def dns(value,presented=False):
    if not 1<=len(value)<=254:return None
    # Root label is optional in textual notation, exactly one dot removed.
    normalized=value[:-1] if value.endswith(b'.') else value
    if not 1<=len(normalized)<=253:return None
    labels=normalized.split(b'.')
    for i,label in enumerate(labels):
        if presented and i==0 and label==b'*':continue
        if not 1<=len(label)<=63 or re.fullmatch(rb'[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?',label) is None:return None
    return normalized.lower()
def match_dns(reference,presented):
    r=dns(reference);p=dns(presented,True)
    if r is None or p is None:return None
    a=r.split(b'.');b=p.split(b'.')
    return len(a)==len(b) and all(x==y or (i==0 and y==b'*') for i,(x,y) in enumerate(zip(a,b)))
def matched(cert,reference,kind):
    return any((kind==0 and tag==130 and match_dns(reference,value) is True) or (kind==1 and tag==135 and reference==value) for tag,value,_ in sans(cert))
def ref_words(kind,value):return [kind,len(value),*value,*bytes(253-len(value))]
def record(op,r=b'',p=b'',cert=b'',layout=0,mode=0,kind=0,max_input=16384,items=100000,work=8388608,repeat=1,code=None,value=None,late=0):
    header=[op,layout,mode,kind,max_input,items,work,len(r),len(p),len(cert),repeat];wire=struct.pack('<11Q',*[n&ANY for n in header])+r+p+cert
    payload=[];offset=0;ii=0;ww=0
    if op in (5,9):ii=ANY;ww=ANY
    if code is None:
        invalid_r=mode in (1,2,3);invalid_p=mode in (4,5,6)
        if invalid_r or (invalid_p and op in (2,4)):code=1
        elif op in (0,1,8):
            result=dns(r,op==1);code=2 if result is None else 0;value=0 if result is None else len(result)
            if code==0 and op==0:payload=ref_words(0,result)
        elif op==2:
            result=match_dns(r,p);code=2 if result is None else 0;value=int(result or False)
        elif op in (3,4):
            code=3 if len(r) not in (4,16) or (op==4 and len(p) not in (4,16)) else 0
            value=0 if code else (len(r) if op==3 else int(r==p))
            if code==0 and op==3:payload=ref_words(1,r)
        elif op==6:
            first=dns(r);second=dns(p);assert first and second
            code=0;value=0;payload=ref_words(0,first)+ref_words(0,b'*'+first[1:])+ref_words(0,second)
        else:code=0;value=int(matched(cert,r,kind))
    if value is None:value=0
    if code and code>=100 and code not in (101,102):offset=ANY
    if op in (5,9) and code==4:
        ii=items;ww=work if mode in (8,9) else work+0-(len(dns(r))+1)
    if op==5 and code==104 and work<len(dns(r))+1:offset=0;ii=items;ww=work
    want=[code,offset,value,ii,ww]+payload
    if op in (5,9) and repeat==2:want+=want
    return wire,want,late
def both(cases,*args,**kw):
    for layout in (0,1):cases.append(record(*args,layout=layout,**kw))

def raw_records():
    cases=[];maximum=b'.'.join([b'a'*63,b'b'*63,b'c'*63,b'd'*61])
    good=[b'a',b'localhost',b'Api.Example.Test',b'Api.Example.Test.',b'127.0.0.1',b'999.0.2.1',b'123',b'a.123',b'1.a',b'a--b.example',b'xn--bcher-kva.example',b'a'*63+b'.test',maximum,maximum+b'.']
    bad=[b'',b'.',b'..',b'a..b',b'.a',b'a..',b'-a.test',b'a-.test',b'_srv.test',b'a b.test',b'a\0b.test',b'\xc3\xa9.test',b'a'*64+b'.test',maximum+b'e',b'http://a.test',b'a.test:443',b'[::1]',b'*',b'*.test',b'a.*.test',b'a*.test']
    for value in good+bad:
        both(cases,0,value);both(cases,8,value);both(cases,1,value)
    for value in [b'*',b'*.test',b'*.xn--bcher-kva.example',b'*.1',b'*.example.test.',b'*.*.test',b'**.test',b'a*.test',b'*a.test',b'*.',b'a.*.test']:
        both(cases,1,value)
    for n in range(256):both(cases,0,b'ab'+bytes([n])+b'cd.example')
    pairs=[(b'Api.Example.Test.',b'api.example.test'),(b'a.example.test',b'*.example.test'),(b'a.b.example.test',b'*.example.test'),(b'example.test',b'*.example.test'),(b'a',b'*'),(b'a.b',b'*'),(b'xn--bcher-kva.example',b'*.example'),(b'127.0.0.1',b'127.0.0.1'),(b'127.0.0.1',b'*.0.0.1'),(b'a.test',b'a*.test'),(b'a.*.test',b'api.test')]
    for r,p in pairs:both(cases,2,r,p)
    rng=random.Random(9525)
    for n in range(128):
        labels=[bytes(rng.choice(b'abCD019-') for _ in range(rng.randrange(1,15))).strip(b'-') or b'z' for _ in range(rng.randrange(1,6))]
        r=b'.'.join(labels);p=r.swapcase() if n%3==0 else (b'.'.join([b'*',*labels[1:]]) if n%3==1 else b'other.'+r)
        if n%4==0:r+=b'.'
        if n%5==0:p+=b'.'
        both(cases,2,r,p)
    for mode in range(1,7):both(cases,2,b'api.test',b'*.test',mode=mode);both(cases,4,bytes(4),bytes(16),mode=mode)
    ips=[bytes(4),bytes([255])*4,ipaddress.ip_address('192.0.2.1').packed,bytes(16),bytes([255])*16,ipaddress.ip_address('2001:db8::1').packed,ipaddress.ip_address('::ffff:192.0.2.1').packed]
    for value in ips:
        both(cases,3,value);both(cases,4,value,value)
        for i in range(len(value)):mut=bytearray(value);mut[i]^=1;both(cases,4,value,bytes(mut))
    for n in range(21):both(cases,3,bytes(n));both(cases,4,bytes(4),bytes(n))
    both(cases,4,ips[2],ips[-1]);both(cases,6,b'Api.Example.Test.',b'Other.Example.Test.')
    return cases

def cert_records():
    cases=[];dns_names=[b'api.example.test',b'API.EXAMPLE.TEST.',b'*.example.test',b'f*.example.test',b'api..example.test',b'api.example.test\0.evil']
    base=[(130,b'api.example.test'),(130,b'*.example.test'),(135,ipaddress.ip_address('192.0.2.1').packed),(135,ipaddress.ip_address('2001:db8::1').packed),(134,b'https://api.example.test')]
    for entries in [None,[(134,b'https://api.example.test')],[(129,b'api.example.test')],*([ (130,n)] for n in dns_names),[(130,b'f*.example.test'),(130,b'api.example.test')],[(130,b'api.example.test'),(130,b'f*.example.test')],base,[(130,b'127.0.0.1')],[(135,bytes([127,0,0,1]))]]:
        cert=certificate(entries)
        for r,kind in [(b'Api.Example.Test.',0),(b'a.example.test',0),(b'a.b.example.test',0),(b'127.0.0.1',0),(bytes([127,0,0,1]),1),(ipaddress.ip_address('192.0.2.1').packed,1),(ipaddress.ip_address('2001:db8::1').packed,1)]:both(cases,5,r,cert=cert,kind=kind)
    cert=certificate(base)
    both(cases,5,b'api.example.test',cert=cert,mode=7)
    both(cases,5,b'api.example.test',cert=cert,repeat=2)
    both(cases,9,b'api.example.test',cert=cert)
    for mode in (8,9,10,11):both(cases,5,b'api.example.test',cert=cert,mode=mode,code=4)
    for kw,code in [({'max_input':len(cert)-1},102),({'max_input':-1},101),({'items':0},103),({'work':0},104),({'work':16},104),({'work':17},104)]:both(cases,5,b'api.example.test',cert=cert,code=code,**kw)
    for code,kw in [(103,{'items':0}),(104,{'work':0})]:both(cases,9,b'api.example.test',cert=cert,code=code,**kw)
    return cases
def budget_records():
    cert=certificate([(130,b'api.example.test'),(130,b'unrelated.example.test')]);late=sans(cert)[-1][2]
    return [record(5,b'api.example.test',cert=cert,layout=layout,late=late) for layout in (0,1)]
def openssl_records():
    cases=[]
    with tempfile.TemporaryDirectory(prefix='laniusc-identity-') as directory:
        root=pathlib.Path(directory);key=root/'key.der';key.write_bytes(bytes.fromhex('302e020100300506032b6570042204209d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60'))
        for entries in ['DNS:api.example.test,DNS:*.example.test,IP:192.0.2.1,IP:2001:db8::1,URI:https://api.example.test',None,'DNS:f*.example.test,DNS:api.example.test']:
            command=['openssl','req','-new','-x509','-keyform','DER','-key',str(key),'-subj','/CN=api.example.test','-days','1','-set_serial','1','-outform','DER']
            if entries:command+=['-addext','subjectAltName='+entries]
            cert=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True,timeout=10).stdout
            for r,kind in [(b'api.example.test',0),(b'A.Example.Test',0),(b'a.b.example.test',0),(b'wrong.test',0),(ipaddress.ip_address('192.0.2.1').packed,1),(ipaddress.ip_address('2001:db8::1').packed,1),(ipaddress.ip_address('192.0.2.2').packed,1)]:both(cases,5,r,cert=cert,kind=kind)
    return cases
def emit(cases):
    out=sys.stdout.buffer;out.write(struct.pack('<Q',len(cases)))
    for wire,want,late in cases:out.write(struct.pack('<Q',len(wire))+wire+struct.pack('<Q',len(want))+struct.pack('<'+'Q'*len(want),*want)+struct.pack('<Q',late))
if __name__=='__main__':emit({'raw':raw_records,'certificates':cert_records,'budgets':budget_records,'openssl':openssl_records}[sys.argv[1]]())
