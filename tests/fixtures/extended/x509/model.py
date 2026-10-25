# Independent host-only schema corpus and mathematical/structural oracle.
# Synthetic signatures deliberately do not authenticate: this tests parsing.
import datetime
import pathlib
import struct
import subprocess
import sys
import tempfile

def tlv(tag, body):
    n = len(body)
    length = bytes([n]) if n < 128 else bytes([128 + (n.bit_length()+7)//8]) + n.to_bytes((n.bit_length()+7)//8, 'big')
    return bytes([tag]) + length + body
def seq(*items): return tlv(48, b''.join(items))
def integer(n):
    width = max(1, (n.bit_length()+8)//8)
    body = n.to_bytes(width, 'big', signed=True)
    while len(body)>1 and int.from_bytes(body[1:],'big',signed=True)==n: body=body[1:]
    return tlv(2,body)
def base128(n):
    groups=[n&127]; n >>= 7
    while n: groups.append((n&127)|128); n >>= 7
    return bytes(reversed(groups))
def oid(*arcs): return tlv(6,base128(40*arcs[0]+arcs[1])+b''.join(base128(n) for n in arcs[2:]))
ED = seq(oid(1,3,101,112))
KEY = bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')
def bits(data, unused=0): return tlv(3,bytes([unused])+data)
def atv(text=b'parser.example', tag=12, attribute=None): return seq(attribute or oid(2,5,4,3),tlv(tag,text))
def name(*attributes): return seq(*(tlv(49,a) for a in attributes))
NAME=name(atv())
def extension(number, body, critical=False, explicit_false=False):
    return seq(oid(2,5,29,number),*( [b'\x01\x01\xff'] if critical else ([b'\x01\x01\0'] if explicit_false else [])),tlv(4,body))
def build(**overrides):
    c=dict(version=2, serial=integer(128), inner=ED, outer=ED, issuer=NAME, subject=NAME,
           validity=seq(tlv(23,b'261024000000Z'),tlv(24,b'20500101000000Z')),
           spki=seq(ED,bits(KEY)), iu=None,su=None,extensions=None,signature=bits(bytes(64)),extra_tbs=b'',extra_outer=b'')
    c.update(overrides); fields=[]
    if c['version'] is not None: fields.append(tlv(160,integer(c['version'])))
    fields += [c[k] for k in ['serial','inner','issuer','validity','subject','spki']]
    if c['iu'] is not None: fields.append(tlv(129,c['iu']))
    if c['su'] is not None: fields.append(tlv(130,c['su']))
    if c['extensions'] is not None: fields.append(tlv(163,seq(*c['extensions'])))
    fields.append(c['extra_tbs'])
    return seq(seq(*fields),c['outer'],c['signature'],c['extra_outer'])

class Node:
    def __init__(self,tag,body,encoded,body_start): self.tag,self.body,self.encoded,self.body_start=tag,body,encoded,body_start
def nodes(data):
    result=[]; at=0
    while at<len(data):
        start=at; tag=data[at]; lead=data[at+1]; at+=2
        if lead&128:
            width=lead&127; assert 1<=width<=4 and data[at]!=0
            size=int.from_bytes(data[at:at+width],'big'); at+=width; assert size>=128
        else: size=lead
        assert at+size<=len(data)
        result.append(Node(tag,data[at:at+size],data[start:at+size],at)); at+=size
    assert at==len(data); return result
def one(data): n=nodes(data); assert len(n)==1; return n[0]
def blob(b): return [len(b),*b]
def ai(n):
    fields=nodes(n.body)
    return blob(fields[0].body)+[int(len(fields)==2)]+(blob(fields[1].encoded) if len(fields)==2 else [])
def bit(n): return [n.body[0]]+blob(n.body[1:])
def nm(n):
    out=blob(n.encoded)
    for rdn in nodes(n.body):
        out += [1]
        for attr in nodes(rdn.body):
            fields=nodes(attr.body);out += [1]+blob(fields[0].body)+blob(fields[1].encoded)
        out += [0]
    return out+[0]
def tm(n):
    b=n.body; width=2 if n.tag==23 else 4
    year=int(b[:width]); year=year+(1900 if year>=50 else 2000) if width==2 else year
    fields=[year]+[int(b[i:i+2]) for i in range(width,width+10,2)]
    datetime.datetime(*fields); return fields
def expected(cert):
    outer=nodes(one(cert).body); fields=nodes(outer[0].body); version=0
    if fields[0].tag==160: version=int.from_bytes(one(fields.pop(0).body).body,'big')
    serial,inner,issuer,validity,subject,spki=fields[:6]; optional=fields[6:]
    dates=nodes(validity.body); public=nodes(spki.body)
    out=[0,version]+blob(serial.body)+blob(outer[0].encoded)+ai(outer[1])+nm(issuer)+nm(subject)+tm(dates[0])+tm(dates[1])+ai(public[0])+bit(public[1])+bit(outer[2])
    exts=[]; ids={}
    for v in optional:
        if v.tag==163: exts=nodes(one(v.body).body)
        else: ids[v.tag]=v
    unknown=0; ext_parts=[]
    for v in exts:
        e=nodes(v.body); critical=len(e)==3; oid_bytes=e[0].body; value=e[-1].body
        kind={b'\x55\x1d\x11':1,b'\x55\x1d\x13':2,b'\x55\x1d\x0f':3,b'\x55\x1d\x25':4}.get(oid_bytes,0)
        unknown+=critical and kind==0
        extra=[]
        if kind==1:
            names=nodes(one(value).body);extra=[sum(n.tag==163 for n in names)]
            for n in names:
                extra += [1,n.tag&31]+blob(n.body)
                if n.tag==164: extra += nm(one(n.body))
                if n.tag==136: extra += blob(n.body)
            extra += [0]
        if kind==2:
            bc=nodes(one(value).body); ca=bool(bc and bc[0].tag==1)
            if ca: bc.pop(0)
            extra=[int(ca),int(bool(bc))]+(blob(bc[0].body) if bc else [])
        if kind==3:
            n=one(value); value_bits=n.body[1:]
            extra=[sum(1<<i for i in range(9) if i//8<len(value_bits) and value_bits[i//8]&(128>>(i%8)))]
        if kind==4:
            for n in nodes(one(value).body): extra += [1]+blob(n.body)
            extra += [0]
        ext_parts += [1,kind]+blob(oid_bytes)+[int(critical)]+blob(value)+extra
    out += [unknown]
    for tag in [129,130]: out += [int(tag in ids)]+(bit(ids[tag]) if tag in ids else [])
    return out+ext_parts+[0]

def records():
    good=[]; bad=[]
    def ok(**kw): good.append(build(**kw))
    def no(code, at_path=None, **kw): bad.append((code,build(**kw),at_path))
    ok();ok(version=None);ok(version=1,iu=b'\x07\x80',su=b'\x00\x55')
    for n in [1,127,128,255,256,(1<<159)-1,(1<<400)+9]:ok(serial=integer(n))
    for alg in [seq(oid(1,2,840,113549,1,1,11),b'\x05\0'),seq(oid(1,2,840,10045,4,3,2)),seq(oid(2,(1<<80)+5,9),seq())]:
        ok(inner=alg,outer=alg,spki=seq(seq(oid(1,2,3,4),seq()),bits(b'generic-kex',3)),signature=bits(b'structure-only'))
    for value,tag in [(b'Caf\xc3\xa9',12),(b"AZ09 '()+,-./:=?",19),(b'legacy',20),(b'\0A\0B',30),(b'\0\0\x01\0',28),(b'a\0b',12)]:ok(subject=name(atv(value,tag)))
    sorted_set=sorted([atv(b'a'),atv(b'b')]);ok(subject=seq(tlv(49,b''.join(sorted_set))))
    for ca,path in [(False,None),(True,None),(True,0),(True,1),(True,(1<<100)+5)]:
        body=seq(*([b'\x01\x01\xff'] if ca else []),*([integer(path)] if path is not None else []));ok(extensions=[extension(19,body,True)])
    for index in range(9):
        content=bytes([128>>index]) if index<8 else bytes([0,128]);unused=7-index if index<8 else 7
        ok(extensions=[extension(15,bits(content,unused),True)])
    ok(extensions=[extension(15,bits(b'\xff\x80',7)),extension(37,seq(oid(1,3,6,1,5,5,7,3,1),oid(2,(1<<80)+9,3)))])
    ok(extensions=[extension(37,seq(oid(1,2,3),oid(1,2,3)))]) # SEQUENCE duplicates are not a DER error.
    general=[tlv(129,b'mail@example.test'),tlv(130,b'parser.example'),tlv(134,b'https://parser.example/path'),tlv(135,bytes([192,0,2,1])),tlv(135,bytes(range(16))),tlv(136,one(oid(2,(1<<80)+3)).body),tlv(164,NAME),tlv(160,oid(1,2,3)+tlv(160,integer(7))),tlv(165,tlv(160,tlv(12,b'assigner'))+tlv(161,tlv(19,b'party'))),tlv(163,seq())]
    for gn in general:ok(extensions=[extension(17,seq(gn))])
    ok(extensions=[extension(17,seq(*general),True)]);ok(subject=seq(),extensions=[extension(17,seq(tlv(130,b'empty-subject.example')),True)])
    ok(extensions=[extension(99,integer(7),True),extension(100,seq(),False)])
    no(8,serial=integer(0));no(8,serial=integer(-1));no(5,serial=tlv(2,b'\0\x01'))
    no(15,version=0);no(7,version=3);no(7,version=None,iu=b'\0x');no(7,version=1,extensions=[extension(99,integer(7))])
    no(9,outer=seq(oid(1,3,101,113)));no(9,inner=seq(oid(1,3,101,112),b'\x05\0'),outer=seq(oid(1,3,101,112),b'\x05\0'))
    no(9,inner=seq(oid(1,3,101,110)),outer=seq(oid(1,3,101,110)))
    for invalid_any in [tlv(16,b''),tlv(17,b''),tlv(55,b'261024000000Z'),tlv(56,b'20500101000000Z')]:
        alg=seq(oid(1,2,3,4),invalid_any)
        no(15,inner=alg,outer=alg)
        no(15,subject=name(seq(oid(1,2,3,4),invalid_any)))
        no(15,at_path=[0,7,0,0,1],extensions=[extension(99,invalid_any)])
    no(9,signature=bits(bytes(63)));no(12,spki=seq(ED,bits(bytes(31))));no(9,spki=seq(seq(oid(1,3,101,112),b'\x05\0'),bits(KEY)))
    no(10,issuer=seq());no(10,subject=seq());no(10,subject=seq(tlv(49,b'')))
    no(15,subject=seq(tlv(49,b''.join(reversed(sorted_set)))))
    no(5,subject=name(atv(b'\xc0\x80',12)));no(5,subject=name(atv(b'@',19)));no(10,subject=name(atv(b'\xd8\0',30)))
    no(6,subject=seq(tlv(49,seq(oid(2,5,4,3)))))
    no(6,extra_tbs=integer(9));no(6,extra_outer=integer(9))
    no(5,validity=seq(tlv(23,b'261024000060Z'),tlv(24,b'20500101000000Z')))
    no(5,validity=seq(tlv(23,b'261024000000Z'),tlv(24,b'20500101000000.1Z')))
    # Ordering and trust/clock comparison are deliberately separate policy.
    ok(validity=seq(tlv(24,b'20500101000000Z'),tlv(23,b'261024000000Z')))
    no(13,extensions=[]);no(14,extensions=[extension(99,integer(1)),extension(99,integer(2))])
    no(15,extensions=[extension(99,integer(1),explicit_false=True)]);no(5,extensions=[extension(99,b'\x02')])
    no(15,extensions=[extension(19,seq(b'\x01\x01\0'))]);no(13,extensions=[extension(19,seq(integer(0)))]);no(13,extensions=[extension(19,seq(b'\x01\x01\xff',integer(-1)))])
    no(15,extensions=[extension(15,bits(b'\x80',0))]);no(15,extensions=[extension(15,bits(b'\0',7))]);no(13,extensions=[extension(15,bits(b'',0))]);no(13,extensions=[extension(15,bits(b'\0\xc0',6))])
    no(13,extensions=[extension(37,seq())]);no(5,extensions=[extension(37,seq(tlv(6,b'\x80\0')))])
    no(13,extensions=[extension(17,seq())]);no(10,subject=seq(),extensions=[extension(17,seq(tlv(130,b'host')))])
    for gn in [tlv(130,b''),tlv(130,b'\xff'),tlv(135,b'12345'),tlv(137,b'unknown'),tlv(162,b'host'),tlv(136,b'\x80\0'),tlv(160,oid(1,2,3)+integer(1)),tlv(165,tlv(160,tlv(12,b'assigner')))]:
        no(5 if gn in [tlv(130,b'\xff'),tlv(136,b'\x80\0')] else (6 if gn==tlv(165,tlv(160,tlv(12,b'assigner'))) else 13),extensions=[extension(17,seq(gn))])
    # Truncate outer framing at every boundary of one small valid certificate.
    small=build(version=None)
    bad += [(5,small[:n],None) for n in range(len(small))]
    result=[]
    for cert in good:
        for layout in [0,1]:result.append((cert,layout,0,16384,1000000,134217728,expected(cert)))
    for code,cert,at_path in bad:
        want=[-code]
        if at_path is not None:
            # Locate actual nested TLV content by independent header lengths,
            # not a source constant or a reproduction of parser error routing.
            n=one(cert);offset=n.body_start
            for index in at_path:
                n=nodes(n.body)[index];offset+=n.body_start
            assert 0<offset<len(cert);want.append(offset)
        for layout in [0,1]:result.append((cert,layout,0,16384,1000000,134217728,want))
    cert=build()
    for layout in [0,1]:
        for mode in [1,2,3]:result.append((cert,layout,mode,16384,1000,100000,[-1]))
        for max_input,items,work,code in [(len(cert)-1,1000,100000,2),(0xffffffff,1000,100000,1),(16384,0,100000,3),(16384,1000,0,4),(16384,1,100000,3),(16384,1000,len(cert),4)]:result.append((cert,layout,0,max_input,items,work,[-code]))
    return result

def openssl_records():
    result=[]
    with tempfile.TemporaryDirectory(prefix='laniusc-x509-') as directory:
        path=pathlib.Path(directory); config=path/'req.cnf';config.write_text('[req]\nprompt=no\ndistinguished_name=dn\n[dn]\nCN=parser.example\nO=Borrowed parser\n')
        for kind in ['ED25519','RSA','EC']:
            key=path/(kind+'.key')
            if kind=='ED25519':
                key.write_bytes(bytes.fromhex('302e020100300506032b6570042204209d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')); key_args=['-keyform','DER','-key',str(key)]
            elif kind=='RSA':key_args=['-newkey','rsa:2048','-noenc','-keyout',str(key)]
            else:key_args=['-newkey','ec','-pkeyopt','ec_paramgen_curve:P-256','-noenc','-keyout',str(key)]
            command=['openssl','req','-new','-x509',*key_args,'-config',str(config),'-subj','/CN=parser.example/O=Borrowed parser','-days','1','-set_serial','128','-outform','DER','-addext','basicConstraints=critical,CA:TRUE,pathlen:2','-addext','keyUsage=critical,digitalSignature,keyCertSign,cRLSign','-addext','extendedKeyUsage=serverAuth,clientAuth','-addext','subjectAltName=DNS:parser.example,IP:192.0.2.1,URI:https://parser.example/path']
            cert=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True,timeout=10).stdout
            root=nodes(one(cert).body); assert len(root)==3 and root[0].tag==48 and root[1].tag==48 and root[2].tag==3
            f=nodes(root[0].body); assert int.from_bytes(f[1].body,'big')==128 and f[0].tag==160
            assert b'parser.example' in cert and len(nodes(f[6].body)[1].body)>30
            if kind=='ED25519':assert nodes(f[6].body)[1].body[1:]==KEY
            for layout in [0,1]:result.append((cert,layout,0,16384,1000000,134217728,expected(cert)))
    return result

corpus=records() if sys.argv[1]=='models' else openssl_records()
out=sys.stdout.buffer;out.write(struct.pack('<Q',len(corpus)))
for cert,layout,mode,max_input,items,work,want in corpus:
    wire=struct.pack('<6Q',layout,mode,max_input,items,work,len(cert))+cert
    out.write(struct.pack('<Q',len(wire))+wire)
    # Negative first word denotes expected error class, offset checked separately.
    out.write(struct.pack('<Q',len(want))+struct.pack('<'+'Q'*len(want),*[n&((1<<64)-1) for n in want]))
