"""Test-only OpenSSL peer; production dispatch has no foreign backend."""
import ctypes as C
import hashlib
import importlib.util
from pathlib import Path
import struct
import sys

ROOT=Path(__file__).parent
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
rsa=module('rsa_peer',ROOT.parent/'rsa/model.py')
ec=module('p256_peer',ROOT.parent/'p256/model.py')
lib=rsa.lib;P=C.c_void_p;I=C.c_int
lib.EVP_MD_CTX_new.restype=P;lib.EVP_MD_CTX_free.argtypes=[P]
lib.EVP_DigestVerifyInit.argtypes=[P,C.POINTER(P),P,P,P];lib.EVP_DigestVerifyInit.restype=I
lib.EVP_DigestVerify.argtypes=[P,P,C.c_size_t,P,C.c_size_t];lib.EVP_DigestVerify.restype=I
lib.EVP_DigestSignInit.argtypes=[P,C.POINTER(P),P,P,P];lib.EVP_DigestSignInit.restype=I
lib.EVP_DigestSign.argtypes=[P,P,C.POINTER(C.c_size_t),P,C.c_size_t];lib.EVP_DigestSign.restype=I
lib.d2i_AutoPrivateKey.argtypes=[C.POINTER(P),C.POINTER(P),C.c_long];lib.d2i_AutoPrivateKey.restype=P
lib.EVP_PKEY_get_raw_public_key.argtypes=[P,P,C.POINTER(C.c_size_t)];lib.EVP_PKEY_get_raw_public_key.restype=I
seq=rsa.seq;tlv=rsa.tlv;integer=rsa.integer;NULL=rsa.NULL
EDOID=tlv(6,bytes.fromhex('2b6570'));ECOID=tlv(6,bytes.fromhex('2a8648ce3d0201'));CURVE=tlv(6,bytes.fromhex('2a8648ce3d030107'));ECSIG=tlv(6,bytes.fromhex('2a8648ce3d040302'))
EDALG=seq(EDOID);ECALG=seq(ECSIG)
def spki(oid,parameters,raw,unused=0):return seq(seq(oid,parameters),tlv(3,bytes([unused])+raw))
def verify_openssl(key,scheme,message,signature):
    encoded=key['spki'];buffer=C.create_string_buffer(encoded);at=P(C.addressof(buffer));public=lib.d2i_PUBKEY(None,C.byref(at),len(encoded));assert public
    context=lib.EVP_MD_CTX_new();assert context
    try:
        operation=P();assert lib.EVP_DigestVerifyInit(context,C.byref(operation),None if scheme==0 else lib.EVP_sha256(),None,public)==1
        if scheme>=2:
            assert lib.EVP_PKEY_CTX_set_rsa_padding(operation,6 if scheme==3 else 1)==1
            if scheme==3:
                assert lib.EVP_PKEY_CTX_set_rsa_mgf1_md(operation,lib.EVP_sha256())==1
                assert lib.EVP_PKEY_CTX_set_rsa_pss_saltlen(operation,32)==1
        return lib.EVP_DigestVerify(context,signature,len(signature),message,len(message))==1
    finally:lib.EVP_MD_CTX_free(context);lib.EVP_PKEY_free(public)

def ed_private(seed):
    encoded=seq(integer(0),EDALG,tlv(4,tlv(4,seed)));buffer=C.create_string_buffer(encoded);at=P(C.addressof(buffer));key=lib.d2i_AutoPrivateKey(None,C.byref(at),len(encoded));assert key
    return key
def ed_sign(seed,message):
    key=ed_private(seed);context=lib.EVP_MD_CTX_new();assert context
    try:
        assert lib.EVP_DigestSignInit(context,None,None,None,key)==1
        length=C.c_size_t(64);output=C.create_string_buffer(64)
        assert lib.EVP_DigestSign(context,output,C.byref(length),message,len(message))==1 and length.value==64
        return output.raw
    finally:lib.EVP_MD_CTX_free(context);lib.EVP_PKEY_free(key)
def keys():
    row=(ROOT.parent/'ed25519/rfc8032.tsv').read_text().splitlines()[1].split('\t');seed=bytes.fromhex(row[1]);public=bytes.fromhex(row[2])
    d=int('c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721',16);point=ec.encode(ec.mul(d));n,e,private=rsa.test_key()
    return [dict(kind=0,spki=spki(EDOID,b'',public),public=public,seed=seed),dict(kind=1,spki=spki(ECOID,CURVE,point),public=point,d=d),dict(kind=2,spki=rsa.spki(n,e),n=n,e=e,d=private)]
def sign(key,message,scheme):
    if scheme==0:result=ed_sign(key['seed'],message)
    elif scheme==1:
        raw=ec.sign_model(key['d'],message,7);result=ec.der(int.from_bytes(raw[:32],'big'),int.from_bytes(raw[32:],'big'))
    else:result=rsa.sign((key['n'],key['e'],key['d']),message,scheme-2)
    assert verify_openssl(key,scheme,message,result)
    return result
def q(*values):return struct.pack('<'+'Q'*len(values),*(v%(1<<64) for v in values))
def pattern(n):return bytes((i*71+i//13+29)&255 for i in range(n))
BIG=1_073_741_824
def common(data):return len(data)+128
def import_work(key):
    cost=common(key['spki'])
    if key['kind']==0:return cost+32
    if key['kind']==1:return cost+1_048_576
    n,e=key['n'],key['e']
    return cost*2+common(rsa.pkcs(n,e))+rsa.size(n)+128+rsa.setup((n.bit_length()+31)//32)
def hash_work(n,wide=False):return n+1024*((n+(144 if wide else 72))//(128 if wide else 64))+4096
def verify_work(key,scheme,message):
    if scheme==0:return 67_108_864+hash_work(len(message)+64,True)
    if scheme==1:return 33_554_432+hash_work(len(message))
    return rsa.verify_work(key['n'],key['e'],scheme-2)+rsa.hash_work(len(message))
class Action:
    def __init__(self,message,signature,scheme,use=0,maximum=1_048_576,attempts=64,work=BIG,bad=0,variant=0,reuse=False):
        self.message,self.signature,self.scheme,self.use=message,signature,scheme,use
        self.maximum,self.attempts,self.work,self.bad,self.variant,self.reuse=maximum,attempts,work,bad,variant,reuse
class Block:
    def __init__(self,key=None,op=0,data=None,layout=0,maximum=1_048_576,attempts=64,work=BIG,bad=0,variant=0,copied=False,actions=(),id=0,use=0,error=0,charged=None,value=None):
        self.key,self.op,self.layout=key,op,layout;self.data=key['spki'] if data is None and key else b'' if data is None else data
        self.maximum,self.attempts,self.work,self.bad,self.variant,self.copied=maximum,attempts,work,bad,variant,copied
        self.actions=list(actions);self.id,self.use,self.error,self.charged,self.value=id,use,error,charged,value
    def outcome(self):
        if self.op==2:
            scheme={0x0807:0,0x0403:1,0x0804:3,0x0401:2}.get(self.id)
            if scheme is None or scheme==2 and self.use:return (6,0,self.work,self.attempts)
            return (0,scheme+1,self.work,self.attempts)
        if self.op==3:return (2 if self.maximum<0 else 0,0,self.work,self.attempts)
        if self.bad:return (1,0,self.work,self.attempts)
        if self.maximum<0:return (2,0,self.work,self.attempts)
        charged=self.charged if self.charged is not None else import_work(self.key) if self.op==0 else common(self.data)
        assert charged<=self.work,(charged,self.work)
        value=0 if self.error else self.key['kind']+1 if self.op==0 else self.value+1
        return (self.error,value,self.work-charged,self.attempts)

def response(key,a,state):
    maximum,attempts,work=state if a.reuse else (a.maximum,a.attempts,a.work)
    status=0;accepted=False;scheme=a.scheme
    if a.bad:status=1
    elif maximum<0:status=2
    elif len(a.message)>maximum:status=3
    elif a.use and scheme==2:status=6
    elif key['kind']!=(scheme if scheme<2 else 2):status=9
    elif scheme==0 and len(a.signature)!=64 or scheme==1 and not 8<=len(a.signature)<=72 or scheme>=2 and len(a.signature)!=rsa.size(key['n']):status=10
    else:
        if scheme==1:
            cost=common(a.signature)
            if cost>work:status=4
            else:
                work-=cost
                try:ec.parse_der(a.signature)
                except ec.Failure:status=10
        if not status:
            if not attempts:status=5
            else:
                cost=verify_work(key,scheme,a.message)
                if cost>work:status=4
                else:work-=cost;attempts-=1;accepted=verify_openssl(key,scheme,a.message,a.signature)
    return q(status,int(accepted),work,attempts),(maximum,attempts,work)

def matrix():
    available=keys();message=pattern(59);blocks=[]
    for layout in [0,1]:
        for key in available:
            own=key['kind'] if key['kind']<2 else 3;signature=sign(key,message,own);actions=[]
            for scheme in range(4):
                actual=sign(key,message,scheme) if key['kind']==(scheme if scheme<2 else 2) else signature
                for use in [0,1]:actions.append(Action(message,actual,scheme,use))
            for length in [0,1,31,32,63,64,65,130,16384]:
                value=pattern(length);signature=sign(key,value,own);actions.extend([Action(value,signature,own),Action(value,signature,own,1)])
            blocks.append(Block(key,layout=layout,copied=True,actions=actions))
    # Independent published RFC8032 + RFC6979 + NIST positive anchors.
    ed,point,_=available
    for line in (ROOT.parent/'ed25519/rfc8032.tsv').read_text().splitlines()[1:4]:
        _,seed,pub,msg,sig=line.split('\t');key=dict(kind=0,public=bytes.fromhex(pub),spki=spki(EDOID,b'',bytes.fromhex(pub)))
        msg,sig=bytes.fromhex(msg),bytes.fromhex(sig);assert verify_openssl(key,0,msg,sig)
        blocks.append(Block(key,actions=[Action(msg,sig,0)]))
    raw=bytes.fromhex('efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8')
    sig=ec.der(int.from_bytes(raw[:32],'big'),int.from_bytes(raw[32:],'big'));assert verify_openssl(point,1,b'sample',sig)
    compressed=dict(point,spki=spki(ECOID,CURVE,ec.encode(ec.decode(point['public']),True)))
    blocks.append(Block(compressed,layout=1,copied=True,actions=[Action(b'sample',sig,1)]))
    for line in (ROOT.parent/'rsa/nist-sha256.tsv').read_text().splitlines():
        if line.startswith('#'):continue
        scheme,bits,n,e,msg,sig,result,salt=line.split('\t')
        if bits=='2048' and result=='1' and (scheme=='0' or salt=='32'):
            key=dict(kind=2,n=int(n,16),e=int(e));key['spki']=rsa.spki(key['n'],key['e']);msg,sig=bytes.fromhex(msg),bytes.fromhex(sig);scheme=int(scheme)+2
            assert verify_openssl(key,scheme,msg,sig);blocks.append(Block(key,actions=[Action(msg,sig,scheme)]))
    for bits in [2049,4096]:
        n,e,d=rsa.generate(bits);key=dict(kind=2,n=n,e=e,d=d,spki=rsa.spki(n,e));value=pattern(130);actions=[]
        for scheme in [2,3]:actions.append(Action(value,sign(key,value,scheme),scheme))
        if bits==2049:actions.append(Action(value,rsa.sign_em((n,e,d),rsa.mag(1<<2048)),3))
        blocks.append(Block(key,layout=1,copied=True,actions=actions))
    return blocks

def mutations():
    blocks=[];message=pattern(130)
    for key in keys():
        actions=[]
        for scheme in ([key['kind']] if key['kind']<2 else [2,3]):
            signature=sign(key,message,scheme)
            for at in range(0,len(signature),max(1,len(signature)//32)):
                changed=bytearray(signature);changed[at]^=1;actions.append(Action(message,bytes(changed),scheme))
            actions.extend([Action(message+b'x',signature,scheme),Action(hashlib.sha256(message).digest(),signature,scheme)])
        for layout in [0,1]:blocks.append(Block(key,layout=layout,copied=True,actions=actions))
    return blocks

def encodings():
    available=keys();blocks=[]
    def error(data,status,op=0,charge=None,**kw):blocks.append(Block(op=op,data=data,error=status,charged=common(data) if charge is None else charge,**kw))
    for layout in [0,1]:
        for key in available:blocks.append(Block(key,layout=layout))
        ed,point,rkey=available
        for data in [b'',ed['spki'][:-1],ed['spki']+b'\0',seq(seq(EDOID),tlv(3,b'\0'+ed['public']),NULL)]:error(data,8,layout=layout)
        for data in [spki(EDOID,NULL,ed['public']),spki(ECOID,b'',point['public']),spki(ECOID,NULL,point['public']),spki(ECOID,rsa.oid(1),point['public'])]:error(data,7,layout=layout)
        for data in [spki(EDOID,b'',ed['public'][:-1]),spki(EDOID,b'',ed['public'],1),spki(ECOID,CURVE,b'\0'),spki(ECOID,CURVE,bytes(65))]:error(data,8,layout=layout)
        data=spki(ECOID,CURVE,b'\x04'+bytes(64));error(data,8,charge=common(data)+1_048_576,layout=layout)
        for data in [spki(rsa.oid(10),rsa.seq(),rsa.pkcs(rkey['n'],rkey['e'])),spki(tlv(6,b'\x2b\x65\x6e'),b'',ed['public'])]:error(data,6,layout=layout)
        for params in [b'',integer(0)]:
            data=rsa.spki(rkey['n'],rkey['e'],params=params);error(data,7,charge=2*common(data),layout=layout)
        data=rsa.spki(rkey['n'],2);error(data,8,charge=2*common(data)+common(rsa.pkcs(rkey['n'],2)),layout=layout)
        for op in [0,1]:
            for variant in [0,1,2]:error(ed['spki'] if op==0 else EDALG,1,op,0,bad=1,variant=variant,layout=layout)
            error(ed['spki'] if op==0 else EDALG,2,op,0,maximum=-1,layout=layout)
            error(bytes(1025 if op==0 else 257),3,op,0,layout=layout)
        for data,scheme in [(EDALG,0),(ECALG,1),(rsa.PKCS_ALG,2),(seq(rsa.oid(11)),2),(rsa.pss_alg(),3),(rsa.pss_alg(null=False),3)]:blocks.append(Block(op=1,data=data,value=scheme,charged=common(data)*(2 if scheme>=2 else 1),layout=layout))
        for data in [b'',EDALG+b'\0',seq(EDOID,NULL),seq(ECSIG,NULL),seq(EDOID,NULL,NULL)]:error(data,7,1,layout=layout)
        for data in [seq(rsa.oid(10)),rsa.pss_alg(20),rsa.pss_alg(hash256=False),rsa.pss_alg(mgf256=False)]:error(data,7,1,2*common(data),layout=layout)
        error(seq(rsa.oid(12),NULL),6,1,layout=layout)
    for id in [0,0x0401,0x0403,0x0804,0x0807,0x0809,0x0501,0x0503,0x0201,0xffff]:
        for use in [0,1]:blocks.append(Block(op=2,id=id,use=use,maximum=-1,work=0,attempts=0))
    for maximum in [-1,0,1]:blocks.append(Block(op=3,maximum=maximum,work=0,attempts=0))
    return blocks

def budgets():
    blocks=[];message=pattern(33)
    for key in keys():
        prefix=common(key['spki']);total=import_work(key)
        for work,charge in [(0,0),(prefix-1,0),(prefix,prefix),(total-1,prefix if key['kind']<2 else total-rsa.setup((key['n'].bit_length()+31)//32)),(total,total)]:
            blocks.append(Block(key,work=work,error=0 if work==total else 4,charged=charge))
        actions=[]
        for scheme in ([key['kind']] if key['kind']<2 else [2,3]):
            signature=sign(key,message,scheme);parse=common(signature) if scheme==1 else 0;cost=parse+verify_work(key,scheme,message)
            for work in [0,max(0,parse-1),parse,cost-1,cost,cost+1]:actions.append(Action(message,signature,scheme,work=work,attempts=1))
            actions.append(Action(message,signature,scheme,work=cost,attempts=0))
            for target in [1,2]:
                for variant in [0,1,2]:actions.append(Action(message,signature,scheme,bad=target,variant=variant,maximum=-1,attempts=0,work=0))
            for maximum in [-1,0,len(message)-1]:actions.append(Action(message,signature,scheme,maximum=maximum,attempts=0,work=0))
            for length in [0,7,73,255,513]:actions.append(Action(message,bytes(length),scheme,attempts=0,work=0))
            if scheme==1:
                malformed=b'\x30\x06\x02\x01\0\x02\x01\1'
                actions.extend([Action(message,malformed,scheme,attempts=0),Action(message,malformed,scheme,work=common(malformed)-1)])
            # A shared post-import allowance: failure consumes one, quota then
            # exhausts without work, followed by an explicit fresh allowance.
            changed=bytearray(signature);changed[-1]^=1
            actions.extend([Action(message,signature,scheme,attempts=2,work=2*cost),Action(message,bytes(changed),scheme,reuse=True),Action(message,signature,scheme,reuse=True)])
        blocks.append(Block(key,copied=True,actions=actions))
        own=key['kind'] if key['kind']<2 else 3;sig=sign(key,message,own);cost=verify_work(key,own,message)+(common(sig) if own==1 else 0)
        blocks.append(Block(key,attempts=1,work=total+cost,actions=[Action(message,sig,own,reuse=True),Action(message,sig,own,reuse=True)]))
    # Delegated RSA parsing must commit previous stages on parameter/work errors.
    data=rsa.pss_alg(20);first=common(data)
    blocks.extend([Block(op=1,data=data,error=4,charged=first,work=first),Block(op=1,data=data,error=7,charged=2*first,work=2*first)])
    return blocks

def build(blocks):
    wire=q(len(blocks));expected=b'';commands=0
    for b in blocks:
        wire+=q(b.op,b.layout,len(b.data),b.maximum,b.attempts,b.work,b.bad,b.variant,b.copied,len(b.actions),b.id,b.use)+b.data
        result=b.outcome();expected+=q(*result);commands+=1;state=(b.maximum,result[3],result[2])
        if b.actions:assert result[0]==0
        for a in b.actions:
            wire+=q(a.use,a.scheme,len(a.message),len(a.signature),a.maximum,a.attempts,a.work,a.bad,a.variant,a.reuse)+a.message+a.signature
            answer,state=response(b.key,a,state);expected+=answer;commands+=1
    return q(len(wire),commands,len(blocks))+wire+expected
if __name__=='__main__':
    groups={'matrix':matrix,'mutations':mutations,'encodings':encodings,'budgets':budgets}
    sys.stdout.buffer.write(build(groups[sys.argv[1]]()))
