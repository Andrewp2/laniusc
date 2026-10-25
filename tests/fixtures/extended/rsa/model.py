"""Independent test-only RSA peers and binary fixture authoring; no production use."""
import ctypes as C
import ctypes.util
import hashlib
import math
from pathlib import Path
import struct
import sys

ROOT=Path(__file__).parent
P=C.c_void_p
I=C.c_int
lib=C.CDLL(ctypes.util.find_library('crypto'))
lib.d2i_PUBKEY.argtypes=[C.POINTER(P),C.POINTER(P),C.c_long];lib.d2i_PUBKEY.restype=P
lib.EVP_PKEY_free.argtypes=[P]
lib.EVP_PKEY_CTX_new.argtypes=[P,P];lib.EVP_PKEY_CTX_new.restype=P
lib.EVP_PKEY_CTX_free.argtypes=[P]
lib.EVP_PKEY_verify_init.argtypes=[P];lib.EVP_PKEY_verify_init.restype=I
lib.EVP_PKEY_verify.argtypes=[P,P,C.c_size_t,P,C.c_size_t];lib.EVP_PKEY_verify.restype=I
for name in ['EVP_PKEY_CTX_set_rsa_padding','EVP_PKEY_CTX_set_rsa_pss_saltlen']:
    function=getattr(lib,name);function.argtypes=[P,I];function.restype=I
for name in ['EVP_PKEY_CTX_set_signature_md','EVP_PKEY_CTX_set_rsa_mgf1_md']:
    function=getattr(lib,name);function.argtypes=[P,P];function.restype=I
lib.EVP_sha256.restype=P
lib.RSA_new.restype=P;lib.RSA_free.argtypes=[P]
lib.BN_new.restype=P;lib.BN_free.argtypes=[P]
lib.BN_set_word.argtypes=[P,C.c_ulong];lib.BN_set_word.restype=I
lib.BN_num_bits.argtypes=[P];lib.BN_num_bits.restype=I
lib.BN_bn2binpad.argtypes=[P,P,I];lib.BN_bn2binpad.restype=I
lib.BN_generate_prime_ex.argtypes=[P,I,I,P,P,P];lib.BN_generate_prime_ex.restype=I
lib.RSA_generate_key_ex.argtypes=[P,I,P,P];lib.RSA_generate_key_ex.restype=I
lib.RSA_get0_key.argtypes=[P,C.POINTER(P),C.POINTER(P),C.POINTER(P)]


def size(n):return (n.bit_length()+7)//8
def mag(n):return n.to_bytes(max(1,size(n)),'big')
def tlv(tag,body):
    length=len(body)
    encoded=bytes([length]) if length<128 else bytes([128+size(length)])+mag(length)
    return bytes([tag])+encoded+body
def seq(*parts):return tlv(48,b''.join(parts))
def integer(n):
    value=mag(n)
    if value[0]&128:value=b'\0'+value
    return tlv(2,value)
def oid(last):return tlv(6,bytes.fromhex('2a864886f70d0101')+bytes([last]))
NULL=b'\x05\0'
SHA256=tlv(6,bytes.fromhex('608648016503040201'))
SHA1=tlv(6,bytes.fromhex('2b0e03021a'))
def pkcs(n,e):return seq(integer(n),integer(e))
def spki(n,e,params=NULL,key_oid=1,unused=0):return seq(seq(oid(key_oid),params),tlv(3,bytes([unused])+pkcs(n,e)))
def hash_alg(null=True,sha256=True):return seq(SHA256 if sha256 else SHA1,NULL if null else b'')
def pss_alg(salt=32,hash256=True,mgf256=True,null=True):
    return seq(oid(10),seq(tlv(160,hash_alg(null,hash256)),tlv(161,seq(oid(8),hash_alg(null,mgf256))),tlv(162,integer(salt))))
PKCS_ALG=seq(oid(11),NULL)
PREFIX=bytes.fromhex('3031300d060960864801650304020105000420')


def openssl(n,e,message,signature,scheme,digest=False):
    encoded=spki(n,e);buffer=C.create_string_buffer(encoded);at=P(C.addressof(buffer))
    key=lib.d2i_PUBKEY(None,C.byref(at),len(encoded));assert key
    context=lib.EVP_PKEY_CTX_new(key,None);assert context
    try:
        assert lib.EVP_PKEY_verify_init(context)==1
        assert lib.EVP_PKEY_CTX_set_rsa_padding(context,6 if scheme else 1)==1
        assert lib.EVP_PKEY_CTX_set_signature_md(context,lib.EVP_sha256())==1
        if scheme:
            assert lib.EVP_PKEY_CTX_set_rsa_mgf1_md(context,lib.EVP_sha256())==1
            assert lib.EVP_PKEY_CTX_set_rsa_pss_saltlen(context,32)==1
        hashed=message if digest else hashlib.sha256(message).digest()
        return lib.EVP_PKEY_verify(context,signature,len(signature),hashed,len(hashed))==1
    finally:
        lib.EVP_PKEY_CTX_free(context);lib.EVP_PKEY_free(key)


def bn_integer(number):
    length=(lib.BN_num_bits(number)+7)//8;out=C.create_string_buffer(length)
    assert lib.BN_bn2binpad(number,out,length)==length
    return int.from_bytes(out.raw,'big')

def generate(bits,e=65537):
    if bits%2:
        # OpenSSL's SP800-56B RSA generator splits both factors at bits//2:
        # a2049-bit request can return2048. Author this test-only boundary key
        # from independently generated1025/1024-bit primes instead. Python
        # integer arithmetic derives n/d; every signature still needs actual
        # EVP verification, and sign_em separately checks the public pow.
        for attempt in range(16):
            p=lib.BN_new();q=lib.BN_new();assert p and q
            try:
                assert lib.BN_generate_prime_ex(p,(bits+1)//2,0,None,None,None)==1
                assert lib.BN_generate_prime_ex(q,bits//2,0,None,None,None)==1
                a,b=bn_integer(p),bn_integer(q)
            finally:lib.BN_free(p);lib.BN_free(q)
            n=a*b;assert n.bit_length()==bits and a!=b
            order=math.lcm(a-1,b-1)
            if math.gcd(e,order)==1:return n,e,pow(e,-1,order)
        raise AssertionError('bounded odd-size test-key generation exhausted')
    rsa=lib.RSA_new();exponent=lib.BN_new();assert rsa and exponent
    try:
        assert lib.BN_set_word(exponent,e)==1
        assert lib.RSA_generate_key_ex(rsa,bits,exponent,None)==1
        n=P();actual_e=P();d=P();lib.RSA_get0_key(rsa,C.byref(n),C.byref(actual_e),C.byref(d))
        result=(bn_integer(n),bn_integer(actual_e),bn_integer(d));assert result[0].bit_length()==bits and result[1]==e
        return result
    finally:lib.BN_free(exponent);lib.RSA_free(rsa)


def test_key():
    row=next(line for line in (ROOT/'nist-test-keys.tsv').read_text().splitlines() if not line.startswith('#')).split('\t')
    return int(row[0],16),int(row[1]),int(row[2],16)
def sign_em(key,em):
    n,e,d=key;representative=int.from_bytes(em,'big');assert representative<n
    signature=pow(representative,d,n).to_bytes(size(n),'big')
    # Independent Python integer arithmetic checks the raw public operation.
    assert pow(int.from_bytes(signature,'big'),e,n)==representative
    return signature

def mgf(seed,length,hash256=True):
    hash_=hashlib.sha256 if hash256 else hashlib.sha1
    return b''.join(hash_(seed+i.to_bytes(4,'big')).digest() for i in range((length+hash_().digest_size-1)//hash_().digest_size))[:length]
def encoded(n,message,scheme,salt_len=32,mgf256=True):
    digest=hashlib.sha256(message).digest();k=size(n)
    if not scheme:return b'\0\1'+b'\xff'*(k-len(PREFIX)-35)+b'\0'+PREFIX+digest
    bits=n.bit_length()-1;length=(bits+7)//8;salt=bytes((i*37+19)&255 for i in range(salt_len))
    h=hashlib.sha256(bytes(8)+digest+salt).digest();db=bytes(length-salt_len-34)+b'\1'+salt
    masked=bytearray(a^b for a,b in zip(db,mgf(h,len(db),mgf256)));masked[0]&=255>>(length*8-bits)
    return bytes(masked)+h+b'\xbc'

def sign(key,message,scheme,**kw):return sign_em(key,encoded(key[0],message,scheme,**kw))
def pattern(n,salt=7):return bytes((i*73+i//7+salt)&255 for i in range(n))
def q(*values):return struct.pack('<'+'Q'*len(values),*(v%(1<<64) for v in values))
def setup(l):return 64*l*(6*l+16)+4096
def product(l):return 3*l*l+12*l+256
def hash_work(n):return n+64*((n+72)//64)
def verify_work(n,e,scheme):
    bits=n.bit_length();k=size(n);l=(bits+31)//32
    cost=(e.bit_length()+e.bit_count()+2)*product(l)+8*k+4096
    if scheme:
        em=(bits+6)//8;cost+=64*((em-33+31)//32)+hash_work(72)
    return cost
BIG=100_000_000
DEFAULT=16_777_216

class Action:
    def __init__(self,message,signature,scheme=0,digest=False,maximum=1_048_576,work=DEFAULT,bad=0,variant=0):
        self.message,self.signature,self.scheme,self.digest=message,signature,scheme,digest
        self.maximum,self.work,self.bad,self.variant=maximum,work,bad,variant
class Block:
    def __init__(self,n=0,e=65537,format=0,encoded=None,layout=0,work=BIG,maximum=1_048_576,bad=0,variant=0,copied=False,actions=(),error=0,charged=None,algorithm=None):
        self.n,self.e,self.format,self.layout=n,e,format,layout
        self.encoded=(mag(n) if format==0 else pkcs(n,e) if format==1 else spki(n,e)) if encoded is None else encoded
        self.work,self.maximum,self.bad,self.variant,self.copied=work,maximum,bad,variant,copied
        self.actions=list(actions);self.error=error;self.charged=charged;self.algorithm=algorithm
    def constructor(self):
        if self.format==4:return (2 if self.maximum<0 else 0,self.work,0,0,0)
        if self.bad:return (1,self.work,0,0,0)
        if self.maximum<0:return (2,self.work,0,0,0)
        if self.charged is not None:
            charged=self.charged
        elif self.format==3:charged=len(self.encoded)+128
        else:
            raw=size(self.n)+128+setup((self.n.bit_length()+31)//32)
            charged=raw+(len(pkcs(self.n,self.e))+128 if self.format in [1,2] else 0)+(len(self.encoded)+128 if self.format==2 else 0)
        assert charged<=self.work,(charged,self.work)
        if self.error:return (self.error,self.work-charged,0,0,0)
        if self.format==3:return (0,self.work-charged,self.algorithm+1,0,0)
        return (0,self.work-charged,self.n.bit_length(),size(self.n),self.e)


def response(block,action):
    a=action;status=0;accepted=False;left=a.work
    if a.bad:status=1
    elif a.maximum<0:status=2
    elif a.digest and len(a.message)!=32:status=11
    elif len(a.signature)!=size(block.n):status=12
    elif not a.digest and len(a.message)>a.maximum:status=3
    else:
        cost=verify_work(block.n,block.e,a.scheme)+(0 if a.digest else hash_work(len(a.message)))
        if cost>a.work:status=4
        else:
            left-=cost;accepted=openssl(block.n,block.e,a.message,a.signature,a.scheme,a.digest)
    return q(status,int(accepted),left)


def published():
    groups={}
    # The original NIST SigVer15 response file has three SHA256 Result=F
    # records with odd hex: Msg at source line784, S at1204/1211. Keep the
    # TSV verbatim, reject these exact source-format cases, and never invent
    # a leading/trailing nibble to turn them into native byte-vector anchors.
    malformed={
        6:('message',255,'afb7368778d9a330128e0000e12c9233bebafea4363ec000db9063148ecaa1b2'),
        15:('signature',511,'7d6f2a5ae4b015a08506e530290c86b3e112acdcb5fc7cf850657286c5132186'),
        16:('signature',511,'39ab0b5cb41637ebb55b50568d468f76b9351e8c4029f5ffba755f1f08f3bca4'),
    }
    rejected_source=set();anchors=0
    for row,line in enumerate((ROOT/'nist-sha256.tsv').read_text().splitlines(),1):
        if line.startswith('#'):continue
        scheme,bits,n,e,message,signature,result,salt=line.split('\t')
        odd=[(name,len(value)) for name,value in [('message',message),('signature',signature)] if len(value)%2]
        if odd:
            assert row in malformed and int(result)==0 and scheme=='0' and bits=='2048'
            name,length,digest=malformed[row]
            assert odd==[(name,length)] and hashlib.sha256(line.encode()).hexdigest()==digest
            rejected_source.add(row)
            continue
        n,e,scheme=int(n,16),int(e),int(scheme);message,signature=bytes.fromhex(message),bytes.fromhex(signature)
        expected=bool(int(result)) and (not scheme or int(salt)==32)
        actual=openssl(n,e,message,signature,scheme)
        assert actual==expected,('NIST anchor',scheme,bits,result,salt)
        key=(n,e);groups.setdefault(key,[]).append(Action(message,signature,scheme));anchors+=1
    assert rejected_source==set(malformed) and anchors==69
    blocks=[]
    for i,((n,e),actions) in enumerate(groups.items()):
        blocks.append(Block(n,e,format=i%3,layout=i%2,copied=i%3==0,actions=actions))
    # Independent OpenSSL-generated keys cover the unsupported-by-CAVP edges.
    for bits,e in [(2048,3),(2049,65537),(4096,65537),(2048,4294967295)]:
        key=generate(bits,e);n,e,_=key;message=pattern(59,11);actions=[]
        for scheme in [0,1]:
            signature=sign(key,message,scheme);assert openssl(n,e,message,signature,scheme)
            actions.extend([Action(message,signature,scheme),Action(hashlib.sha256(message).digest(),signature,scheme,True),Action(hashlib.sha256(hashlib.sha256(message).digest()).digest(),signature,scheme,True)])
            if bits==4096:
                large=pattern(16384,37);actions.append(Action(large,sign(key,large,scheme),scheme))
            if bits==2049 and scheme:
                # m fits n but cannot fit the required shorter PSS emLen.
                actions.append(Action(message,sign_em(key,mag(1<<2048)),scheme))
        blocks.append(Block(n,e,format=2,layout=bits%2,copied=True,actions=actions))
    return blocks


def rejected():
    key=test_key();n,e,_=key;message=pattern(59,43);actions=[];k=size(n)
    for scheme in [0,1]:
        signature=sign(key,message,scheme);assert openssl(n,e,message,signature,scheme)
        em=encoded(n,message,scheme)
        positions=([0,1,2,k-53,k-52]+list(range(k-51,k))) if not scheme else [0,1,k-67,k-66,k-65,k-34]+list(range(k-33,k))
        top=bytearray(em);top[0]|=128
        if int.from_bytes(top,'big')<n:actions.append(Action(message,sign_em(key,top),scheme))
        for position in sorted(set(positions)):
            altered=bytearray(em);altered[position]^=1
            if int.from_bytes(altered,'big')>=n:continue
            actions.append(Action(message,sign_em(key,altered),scheme))
        # Signature-level mutations cover low/high limbs and representative range.
        for at in [0,1,31,32,63,64,127,128,191,192,254,255]:
            changed=bytearray(signature);changed[at]^=1<<(at%8);actions.append(Action(message,bytes(changed),scheme))
        actions.extend([Action(message,bytes(k),scheme),Action(message,(n-1).to_bytes(k,'big'),scheme),Action(message,n.to_bytes(k,'big'),scheme),Action(message,bytes([255])*k,scheme),Action(message+b'x',signature,scheme)])
        if scheme:
            for salt in [0,20,31,33]:actions.append(Action(message,sign(key,message,scheme,salt_len=salt),scheme))
            actions.append(Action(message,sign(key,message,scheme,mgf256=False),scheme))
        else:
            # Exact DigestInfo: reject missing NULL/extra tail/short FF padding.
            for malformed in [b'\0\1'+b'\xff'*(k-52)+b'\0'+PREFIX[:-4]+PREFIX[-2:]+hashlib.sha256(message).digest(),b'\0\1'+b'\xff'*8+b'\0'+PREFIX+hashlib.sha256(message).digest()+bytes(k-62)]:
                if len(malformed)==k:actions.append(Action(message,sign_em(key,malformed),scheme))
    assert all(not openssl(n,e,a.message,a.signature,a.scheme,a.digest) for a in actions)
    # Repeat in both layouts with copies to catch retained/raw and native strides.
    return [Block(n,e,layout=layout,copied=True,actions=actions) for layout in [0,1]]


def encodings():
    n,e,_=test_key();raw=mag(n);der=pkcs(n,e);sp=spki(n,e);blocks=[]
    def error(format,data,status,charged=None,**kw):
        blocks.append(Block(n,e,format,encoded=data,error=status,charged=(len(data)+128 if charged is None else charged),**kw))
    for layout in [0,1]:
        for format in [0,1,2]:blocks.append(Block(n,e,format,layout=layout))
        for data in [b'',b'\0'+raw,raw[:-1]+bytes([raw[-1]&254]),bytes([raw[0]&127])+raw[1:]]:
            if not data:error(0,data,5,0,layout=layout)
            elif data[0]==0 or data[-1]%2==0:error(0,data,5,len(data)+128,layout=layout)
            else:error(0,data,6,len(data)+128,layout=layout)
        error(0,bytes([1])*513,6,0,layout=layout)
        for exponent in [0,1,2,4,65536]:blocks.append(Block(n,exponent,encoded=raw,error=7,charged=0,layout=layout))
        for data in [b'',der[:-1],der+b'\0',b'\x30\x80'+der[2:]+b'\0\0',seq(integer(n),integer(e),NULL),seq(tlv(2,b'\0'+b'\0'+raw),integer(e)),seq(tlv(2,raw),integer(e)),seq(integer(n),integer(1<<32)),seq(integer(n),integer(2))]:
            status=7 if data in [seq(integer(n),integer(1<<32)),seq(integer(n),integer(2))] else 8
            charged=len(data)+128
            error(1,data,status,charged,layout=layout)
        for data,status in [(sp[:-1],8),(sp+b'\0',8),(spki(n,e,params=b''),10),(spki(n,e,params=integer(0)),10),(spki(n,e,key_oid=10),9),(spki(n,e,unused=1),8)]:error(2,data,status,layout=layout)
        for format in [0,1,2,3]:
            for variant in [0,1,2]:blocks.append(Block(n,e,format,encoded=raw if format==0 else der if format==1 else sp if format==2 else PKCS_ALG,bad=1,variant=variant,layout=layout))
        for format in [0,1,2,3]:blocks.append(Block(n,e,format,maximum=-1,layout=layout))
        # Limits construction is exercised directly, including zero credits/input.
        blocks.extend([Block(format=4,encoded=b'',maximum=-1,work=0),Block(format=4,encoded=b'',maximum=0,work=0)])
        good=[(PKCS_ALG,0),(seq(oid(11)),0),(pss_alg(),1),(pss_alg(null=False),1)]
        for data,scheme in good:blocks.append(Block(format=3,encoded=data,algorithm=scheme,layout=layout))
        wrong=[b'',PKCS_ALG+b'\0',seq(oid(11),integer(0)),seq(oid(11),NULL,NULL),seq(oid(10)),seq(oid(10),seq()),pss_alg(20),pss_alg(31),pss_alg(33),pss_alg(hash256=False),pss_alg(mgf256=False)]
        # Explicit DEFAULT trailer1 is noncanonical DER; duplicate/out-of-order
        # parameter fields and a different MGF OID cannot be silently ignored.
        parameters=seq(tlv(160,hash_alg()),tlv(161,seq(oid(8),hash_alg())),tlv(162,integer(32)))
        wrong.extend([seq(oid(10),seq(parameters[2:],tlv(163,integer(1)))),seq(oid(10),seq(tlv(160,hash_alg()),tlv(160,hash_alg()),tlv(162,integer(32)))),seq(oid(10),seq(tlv(161,seq(oid(8),hash_alg())),tlv(160,hash_alg()),tlv(162,integer(32)))),seq(oid(10),seq(tlv(160,hash_alg()),tlv(161,seq(oid(7),hash_alg())),tlv(162,integer(32))))])
        for data in wrong:error(3,data,10,layout=layout)
        error(3,seq(oid(12),NULL),9,layout=layout)
        error(3,bytes(257),3,0,layout=layout);error(1,bytes(1025),3,0,layout=layout)
    return blocks


def budgets():
    key=test_key();n,e,_=key;raw=mag(n);scan=len(raw)+128;setup_cost=setup((n.bit_length()+31)//32);blocks=[]
    for work,charge_,status in [(0,0,4),(scan-1,0,4),(scan,scan,4),(scan+setup_cost-1,scan,4),(scan+setup_cost,scan+setup_cost,0)]:
        blocks.append(Block(n,e,work=work,error=status,charged=charge_))
    message=pattern(33,53);actions=[]
    for scheme in [0,1]:
        signature=sign(key,message,scheme)
        for digest in [False,True]:
            value=hashlib.sha256(message).digest() if digest else message
            cost=verify_work(n,e,scheme)+(0 if digest else hash_work(len(value)))
            for available in [0,cost-1,cost,cost+1]:actions.append(Action(value,signature,scheme,digest,work=available))
            changed=bytearray(signature);changed[0]^=1;actions.append(Action(value,bytes(changed),scheme,digest,work=cost))
            for target in [1,2]:
                for variant in [0,1,2]:actions.append(Action(value,signature,scheme,digest,work=0,bad=target,variant=variant))
            for maximum in [-1,0,len(message)-1]:actions.append(Action(value,signature,scheme,digest,maximum=maximum))
            for length in [0,31,33]:
                if digest:actions.append(Action(pattern(length),signature,scheme,True))
            for length in [0,len(signature)-1,len(signature)+1]:actions.append(Action(value,pattern(length),scheme,digest))
            # Bounds wins over bad digest/signature sizes and invalid budget.
            actions.append(Action(b'',b'',scheme,digest,maximum=-1,work=0,bad=1))
    blocks.append(Block(n,e,copied=True,actions=actions))
    # DER parse charge is retained when subsequent key setup is refused.
    der=pkcs(n,e);initial=len(der)+128
    blocks.append(Block(n,e,format=1,work=initial,error=4,charged=initial))
    return blocks


def build(blocks):
    wire=q(len(blocks));expected=b'';commands=0
    for b in blocks:
        wire+=q(b.format,b.layout,b.e,len(b.encoded),b.maximum,b.work,b.bad,b.variant,b.copied,len(b.actions))+b.encoded
        outcome=b.constructor();expected+=q(*outcome);commands+=1
        if b.actions:assert outcome[0]==0
        for a in b.actions:
            wire+=q(a.digest,a.scheme,len(a.message),len(a.signature),a.maximum,a.work,a.bad,a.variant)+a.message+a.signature
            expected+=response(b,a);commands+=1
    return wire,expected,commands,len(blocks)

if __name__=='__main__':
    groups={'published':published,'rejected':rejected,'encodings':encodings,'budgets':budgets}
    blocks=groups[sys.argv[1]]();wire,expected,commands,count=build(blocks)
    sys.stdout.buffer.write(q(len(wire),commands,count)+wire+expected)
