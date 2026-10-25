"""Independent test-only multi-key TLS authentication peer, never a backend.

OpenSSL checks certificate paths and verifies every expected proof. Python
constructs the RFC8446 full CertificateVerify input; fixed RSA/P256 helpers
only author signatures, with acceptance obtained from EVP DigestVerify.
"""
import copy
import importlib.util
from pathlib import Path
import struct
import sys
import tempfile

ROOT=Path(__file__).parent
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
peer=module('tls_auth_peer',ROOT/'peer.py')
sig=module('tls_auth_signature_peer',ROOT.parent/'signature/model.py')
Q=peer.Q;FRAME=peer.FRAME;H=peer.H;MAC=peer.MAC;U16=peer.U16;U24=peer.U24
BIG=1<<30;MAX=(1<<64)-1
WITNESS=b'owned TLS leaf key after retirement'
assert len(WITNESS)==35
IDS=(0x0807,0x0403,0x0401,0x0804)
POLICIES={0:(0x0807,0x0403,0x0804),1:(0x0807,),2:(0x0403,),3:(0x0804,),4:(0x0401,),5:(0x0807,0x0807),6:()}

def hello(algorithm,proofs,certificates):
    # Policies mirror the actual emitted offers, including a separate explicit
    # certificate list. Authentication assumes this negotiation boundary.
    ch,sh,_,_,_,_=peer.hello(False,algorithm)
    old=ch[47:];at=0;extensions=[];seen=False
    while at<len(old):
        kind=int.from_bytes(old[at:at+2],'big');n=int.from_bytes(old[at+2:at+4],'big');body=old[at+4:at+4+n];at+=4+n
        if kind==13:
            ids=b''.join(U16(x) for x in POLICIES[proofs]);body=U16(len(ids))+ids;seen=True
        extensions.append(peer.EXT(kind,body))
    assert at==len(old) and seen
    ids=b''.join(U16(x) for x in POLICIES[certificates]);extensions.append(peer.EXT(50,U16(len(ids))+ids))
    extensions=b''.join(extensions)
    body=ch[4:45]+U16(len(extensions))+extensions
    ch=FRAME(1,body);prefix=ch+sh
    public=peer.ctypes.create_string_buffer(32);shared=peer.ctypes.create_string_buffer(32)
    assert peer.SODIUM.crypto_scalarmult_curve25519_base(public,bytes(range(32,64)))==0
    assert peer.SODIUM.crypto_scalarmult_curve25519(shared,bytes(range(32)),public)==0
    size=peer.HASH_LENGTH[algorithm];early=MAC(bytes(size),bytes(size),algorithm)
    derived=peer.expand(early,b'derived',H(b'',algorithm),algorithm=algorithm)
    handshake=MAC(derived,shared.raw,algorithm)
    secret=peer.expand(handshake,b's hs traffic',H(prefix,algorithm),algorithm=algorithm)
    return ch,sh,prefix,secret

def replace_leaf(base,key):
    chain=copy.copy(base);leaf=base.chain[0]
    _,outer,_,end=peer.der(leaf);assert end==len(leaf)
    pieces=peer.members(outer);tbs=peer.members(pieces[0][1]);assert len(tbs)>=7
    encoded=sig.seq(*(item[2] if i!=6 else key['spki'] for i,item in enumerate(tbs)))
    seed=H(b'tls authentication intermediate 0')
    signature=sig.ed_sign(seed,encoded)
    issuer=peer.cert_parts(base.chain[1]);assert peer.verify(issuer['public'],encoded,signature)
    certificate=sig.seq(encoded,pieces[1][2],sig.tlv(3,b'\0'+signature))
    chain.chain=[certificate]+base.chain[1:];chain.key=key
    assert chain.openssl(chain.chain,chain.root,b'server.example',chain.now)
    return chain

def flight(c,variant='ok'):
    ee=FRAME(8,b'\0\0');entries=b''.join(U24(len(cert))+cert+b'\0\0' for cert in c.chain.chain)
    certificate=FRAME(11,b'\0'+U24(len(entries))+entries)
    digest=H(c.prefix+ee+certificate,c.algorithm)
    signed=b' '*64+b'TLS 1.3, server CertificateVerify\0'+digest
    own=1 if c.key['kind']==1 else 3
    signer=c.key;scheme=own;wireid=IDS[own]
    actual=signed
    if variant=='context':actual=b' '*64+b'TLS 1.3, client CertificateVerify\0'+digest
    if variant=='hash':actual=b' '*64+b'TLS 1.3, server CertificateVerify\0'+H(c.prefix+ee+certificate,1-c.algorithm)
    if variant=='digest_only':actual=digest
    if variant=='double_hash':actual=H(signed)
    if variant=='key':signer=c.other
    if variant=='wrong_scheme':wireid=0x0807
    if variant=='pkcs1':scheme=2;wireid=0x0401
    signature=sig.sign(signer,actual,scheme)
    # Expected authentication decision is from EVP on the exact server input.
    valid=wireid==IDS[own] and sig.verify_openssl(c.key,own,signed,signature)
    if variant=='mutation':signature=signature[:-1]+bytes([signature[-1]^1]);valid=sig.verify_openssl(c.key,own,signed,signature)
    if variant=='encoding':signature=b'\x30\x06\x02\x01\0\x02\x01\1' if own==1 else signature[:-1];valid=False
    cv=FRAME(15,U16(wireid)+U16(len(signature))+signature)
    finished=FRAME(20,MAC(peer.expand(c.secret,b'finished',b'',algorithm=c.algorithm),H(c.prefix+ee+certificate+cv,c.algorithm),c.algorithm))
    if variant=='finished':finished=finished[:-1]+bytes([finished[-1]^1])
    return [ee,certificate,cv,finished],wireid,signature,valid,signed

class Case:
    def __init__(self,chain,other,algorithm=0,layout=0,variant='ok',**kw):
        self.chain=chain;self.key=chain.key;self.other=other;self.algorithm=algorithm;self.layout=layout;self.variant=variant
        self.proofs=0;self.certificates=1;self.work=BIG;self.attempts=64;self.cap=MAX;self.quota=MAX;self.messagecap=1048576;self.mutate=1
        self.__dict__.update(kw)
        self.ch,self.sh,self.prefix,self.secret=hello(algorithm,self.proofs,self.certificates)
        self.frames,self.wireid,self.signature,self.valid,self.signed=flight(self,variant)
        own=1 if self.key['kind']==1 else 3
        self.witness=sig.sign(self.key,WITNESS,own)
        assert sig.verify_openssl(self.key,own,WITNESS,self.witness)
    def wire(self):
        _,certificate,cv,fin=self.frames;ownid=0x0403 if self.key['kind']==1 else 0x0804
        return Q(self.layout,self.algorithm,ownid,self.proofs,self.certificates,self.chain.now,self.work,self.attempts,self.cap,self.quota,self.messagecap,len(self.chain.root),len(self.ch),len(self.sh),len(certificate),len(cv),len(fin),len(self.witness),self.mutate)+self.chain.root+self.ch+self.sh+self.secret+self.witness+b''.join(self.frames)

def outcome(c):
    if c.proofs in (4,5,6):return 7,[]
    records=[];prefix=c.prefix;step=0;error=0;attempts=c.attempts;known_work=None
    for index,frame in enumerate(c.frames):
        status=error;rule=1;debit=0
        if not status:
            debit=peer.frame_tariff(c.algorithm,step,len(frame));rule=2
            if step==1:
                rule=3
                if c.certificates==2:status=100
                else:attempts-=2
            if step==2:
                if c.quota<attempts:attempts=c.quota
                own=1 if c.key['kind']==1 else 3
                if c.wireid not in POLICIES[c.proofs] or c.wireid not in (0x0807,0x0403,0x0804):status=7
                elif c.wireid!=IDS[own]:status=7
                elif len(c.signature)!=(len(c.signature) if own==1 else sig.rsa.size(c.key['n'])):status=7
                else:
                    syntax=len(c.signature)+128 if own==1 else 0
                    work=sig.verify_work(c.key,own,c.signed)
                    cap=c.cap
                    if cap<debit:status=9;rule=1;debit=0
                    elif own==1 and cap<debit+syntax:status=9
                    else:
                        debit+=syntax
                        malformed=False
                        if own==1:
                            try:sig.ec.parse_der(c.signature)
                            except sig.ec.Failure:malformed=True
                        if malformed:status=7
                        elif c.messagecap<len(c.signed):
                            # Message preflight precedes the DER charge.
                            debit-=syntax;status=8
                        elif attempts==0:status=10
                        elif cap<debit+work:status=9
                        else:attempts-=1;debit+=work;status=0 if c.valid else 17
            if step==2 and c.cap!=MAX:known_work=c.cap-debit
            if step==3:
                if known_work is not None and known_work<debit:status=9;rule=1;debit=0
                elif c.variant=='finished':status=18
                if known_work is not None:known_work-=debit
            if not status:prefix+=frame;step+=1
            else:error=status
        auth=step==4 and not error
        words=[status,5 if error else step,int(bool(error)),int(auth),int(auth),int(auth),attempts,0]
        words+=list(struct.unpack('<6Q',H(prefix,c.algorithm).ljust(48,b'\0') if auth else bytes(48)))
        words += [6 if auth else 0,c.key['kind']+1 if auth else 0,int(auth)]
        assert len(words)==17
        records.append((rule,debit,c.cap if index==2 else MAX,words))
    return 0,records

def cases(base,mode):
    available=sig.keys();rsa,ec=available[2],available[1]
    wrong_ec=dict(ec,d=ec['d']+1,public=sig.ec.encode(sig.ec.mul(ec['d']+1)))
    wrong_ec['spki']=sig.spki(sig.ECOID,sig.CURVE,wrong_ec['public'])
    # A same-width signature from an independently generated test RSA key.
    n,e,d=sig.rsa.generate(2048);wrong_rsa=dict(kind=2,n=n,e=e,d=d,spki=sig.rsa.spki(n,e))
    materials=[(replace_leaf(base,ec),wrong_ec),(replace_leaf(base,rsa),wrong_rsa)]
    result=[]
    for chain,other in materials:
        for algorithm in (0,1):
            values=['ok'] if mode in ('positive','ordinary') else ['context','hash','digest_only','double_hash','key','wrong_scheme','mutation','encoding','finished']+(['pkcs1'] if chain.key['kind']==2 else [])
            for variant in values:
                for layout in (0,1):result.append(Case(chain,other,algorithm,layout,variant))
            if mode=='negative':
                for layout in (0,1):
                    # Certificate permission is never permission for a proof.
                    result.append(Case(chain,other,algorithm,layout,proofs=1))
                    result.append(Case(chain,other,algorithm,layout,certificates=2))
                    for p in [4,5,6]:result.append(Case(chain,other,algorithm,layout,proofs=p))
                    c=Case(chain,other,algorithm,layout);own=1 if chain.key['kind']==1 else 3
                    tariff=peer.frame_tariff(algorithm,2,len(c.frames[2]));parse=len(c.signature)+128 if own==1 else 0;total=tariff+parse+sig.verify_work(chain.key,own,c.signed)
                    for cap in [tariff-1,tariff,tariff+parse,total-1,total,total+1,total+peer.frame_tariff(algorithm,3,len(c.frames[3]))-1,total+peer.frame_tariff(algorithm,3,len(c.frames[3]))]:
                        result.append(Case(chain,other,algorithm,layout,cap=cap))
                    result.append(Case(chain,other,algorithm,layout,quota=0))
                    result.append(Case(chain,other,algorithm,layout,messagecap=len(c.signed)-1))
    return result

def emit(cases):
    source=Q(len(cases));expected=Q(len(cases))
    for c in cases:
        wire=c.wire();source+=wire;constructor,records=outcome(c)
        expected+=Q(c.layout,constructor,c.work,len(c.chain.root))+c.chain.root+Q(len(records))
        for rule,debit,cap,words in records:expected+=Q(rule,debit,cap)+Q(*words)
    return Q(len(source))+source+Q(len(expected))+expected
if __name__=='__main__':
    with tempfile.TemporaryDirectory(prefix='laniusc_tls_multisignature_') as temp:
        base=peer.Chain(Path(temp)/'chain',2)
        collection=cases(base,sys.argv[1])
        if sys.argv[1]=='ordinary':
            source=Q(len(collection))+b''.join(c.wire() for c in collection)
            expected=b''.join(Q(c.key['kind']+1)+H(c.prefix+b''.join(c.frames),c.algorithm) for c in collection)
            sys.stdout.buffer.write(Q(len(source))+source+Q(len(expected))+expected)
        else:sys.stdout.buffer.write(emit(collection))
