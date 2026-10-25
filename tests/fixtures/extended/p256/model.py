#!/usr/bin/env python3
"""Independent affine bigint model + published vectors + OpenSSL byte oracle.
Test orchestration only. Production never calls this file or an external backend.
"""
import functools,hashlib,pathlib,random,struct,subprocess,sys,tempfile
P=0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff
N=0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551
B=0x5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b
G=(0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296,0x4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5)
HERE=pathlib.Path(__file__).parent
be=lambda n:n.to_bytes(32,'big')
class Failure(Exception):
 def __init__(self,code):self.code=code

def need(b,c):
 if not b:raise Failure(c)
def add(a,b):
 if a is None:return b
 if b is None:return a
 x,y=a;u,v=b
 if x==u:
  if (y+v)%P==0:return None
  slope=(3*x*x-3)*pow(2*y,-1,P)%P
 else:slope=(v-y)*pow(u-x,-1,P)%P
 z=(slope*slope-x-u)%P
 return z,(slope*(x-z)-y)%P
@functools.lru_cache(maxsize=4096)
def mul(k,p=G):
 result=None
 while k:
  if k&1:result=add(result,p)
  p=add(p,p);k//=2
 return result

def encode(p,compressed=False):
 assert p is not None
 x,y=p
 return bytes([2+(y&1)])+be(x) if compressed else b'\x04'+be(x)+be(y)
def decode(raw):
 need(len(raw) in (33,65),4);need(raw[0] in ((2,3) if len(raw)==33 else (4,)),5)
 x=int.from_bytes(raw[1:33],'big');need(x<P,6);rhs=(pow(x,3,P)-3*x+B)%P
 if len(raw)==65:y=int.from_bytes(raw[33:],'big');need(y<P and y*y%P==rhs,6)
 else:
  y=pow(rhs,(P+1)//4,P);need(y*y%P==rhs,6)
  if y&1 != raw[0]&1:y=(-y)%P
  need(y&1==raw[0]&1,6)
 return x,y

def private(raw):need(len(raw)==32,2);k=int.from_bytes(raw,'big');need(0<k<N,3);return k
def verify(pub,digest,signature):
 try:q=decode(pub)
 except Failure:return False
 r=int.from_bytes(signature[:32],'big');s=int.from_bytes(signature[32:],'big')
 if not(0<r<N and 0<s<N):return False
 w=pow(s,-1,N);z=int.from_bytes(digest,'big');point=add(mul(z*w%N),mul(r*w%N,q))
 return point is not None and point[0]%N==r

def der(r,s):
 def integer(n):
  b=n.to_bytes(max(1,(n.bit_length()+7)//8),'big')
  if b[0]&128:b=b'\0'+b
  return b'\x02'+bytes([len(b)])+b
 body=integer(r)+integer(s);return b'\x30'+bytes([len(body)])+body

def parse_der(raw):
 need(8<=len(raw)<=72 and raw[0]==48 and raw[1]==len(raw)-2,9);at=2;values=[]
 for _ in range(2):
  need(len(raw)-at>=2 and raw[at]==2,9);n=raw[at+1];at+=2;need(1<=n<=33 and at+n<=len(raw),9);b=raw[at:at+n];at+=n
  need(b[0]<128 and not(len(b)>1 and b[0]==0 and b[1]<128),9);need(n!=33 or b[0]==0,9);k=int.from_bytes(b,'big');need(0<k<(1<<256),9);values.append(k)
 need(at==len(raw),9);return be(values[0])+be(values[1])

def sign_model(d,msg,k):
 r=mul(k)[0]%N;s=(int.from_bytes(hashlib.sha256(msg).digest(),'big')+r*d)*pow(k,-1,N)%N;assert r and s
 return be(r)+be(s)

def answer(op,mode,a,b,c):
 try:
  need(mode not in (1,2,3) and not(mode==4 and op in (3,4,5)) and not(mode==5 and op in (4,5)),1)
  if op==0:result=encode(mul(private(a)))
  elif op==1:result=encode(decode(a))
  elif op==2:result=encode(decode(a),True)
  elif op==3:
   need(len(a)==32,2);need(len(b) in (33,65),4);result=be(mul(private(a),decode(b))[0])
  elif op in (4,5):
   need(len(a) in (33,65),4)
   if op==4:need(len(b)==32,7)
   need(len(c)==64,8);result=bytes([verify(a,b if op==4 else hashlib.sha256(b).digest(),c)])
  else:result=parse_der(a)
  return [0,len(result),*result]
 except Failure as e:return [e.code,0]

CASES=[]
def case(op,a,b=b'',c=b'',mode=0,layouts=(0,1),expected=None):
 for layout in layouts:
  wire=struct.pack('<6Q',op,layout,mode,len(a),len(b),len(c))+a+b+c
  result=answer(op,mode,a,b,c)
  if expected is not None:assert result==[0,len(expected),*expected],(op,a.hex(),result,expected.hex())
  CASES.append((wire,result))
def records(path):
 result=[];record={}
 for line in path.read_text().splitlines()+['']:
  if line.startswith('#') or line.startswith('['):continue
  if not line.strip():
   if record:result.append(record);record={}
  elif '=' in line:
   k,v=line.split('=',1);record[k.strip()]=v.strip()
 return result
RFC_D=int('c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721',16)
RFC_Q=bytes.fromhex('0460fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb67903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299')
RFC_SIG=bytes.fromhex('efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8')

def published():
 rows=records(HERE/'nist_ecdh.txt');assert len(rows)==25
 for r in rows:
  d=be(int(r['Private'],16));q=b'\x04'+be(int(r['PeerX'],16))+be(int(r['PeerY'],16));public=b'\x04'+be(int(r['X'],16))+be(int(r['Y'],16));secret=be(int(r['Z'],16))
  case(0,d,expected=public);case(1,q,expected=q);case(2,q,expected=encode(decode(q),True));case(3,d,q,expected=secret);case(3,d,encode(decode(q),True),expected=secret)
 rows=records(HERE/'nist_sigver.txt');assert len(rows)==15
 for r in rows:
  q=b'\x04'+be(int(r['Qx'],16))+be(int(r['Qy'],16));msg=bytes.fromhex(r['Msg']);sig=be(int(r['R'],16))+be(int(r['S'],16));ok=bytes([r['Result'].startswith('P')])
  # The verifier accepts malformed curve coordinates as false. Only compress
  # mathematically valid keys, to avoid manufacturing a different public key.
  keys=[q]
  try:keys.append(encode(decode(q),True))
  except Failure:pass
  for key in keys:case(4,key,hashlib.sha256(msg).digest(),sig,expected=ok);case(5,key,msg,sig,expected=ok)
 case(0,be(RFC_D),expected=RFC_Q)
 for q in [RFC_Q,encode(decode(RFC_Q),True)]:
  case(4,q,hashlib.sha256(b'sample').digest(),RFC_SIG,expected=b'\1');case(5,q,b'sample',RFC_SIG,expected=b'\1')
 case(6,der(int.from_bytes(RFC_SIG[:32],'big'),int.from_bytes(RFC_SIG[32:],'big')),expected=RFC_SIG)

def openssl_and_model():
 rng=random.Random(0x256ec);scalars=[1,2,3,7,31,32,255,256,257,(1<<32)-1,1<<32,1<<128,1<<255,N-1]+[rng.randrange(1,N) for _ in range(8)]
 for d in scalars:
  q=encode(mul(d));compressed=encode(mul(d),True);case(0,be(d),expected=q);case(1,compressed,expected=q);case(2,q,expected=compressed)
  peer=mul(rng.randrange(1,N));case(3,be(d),encode(peer));case(3,be(d),encode(peer,True))
 for i in range(12):
  d=rng.randrange(1,N);msg=rng.randbytes([0,1,31,32,33,63,64,65,111,128,255,1024][i]);sig=sign_model(d,msg,rng.randrange(1,N));q=encode(mul(d));case(5,q,msg,sig,expected=b'\1');case(4,q,hashlib.sha256(msg).digest(),sig,expected=b'\1')
 # ECDSA edge equations: u1=0, resulting infinity, and affine X>=n. These
 # directly challenge group exceptions and final x mod n normalization.
 d=7;k=9;r=mul(k)[0]%N;s=r*d*pow(k,-1,N)%N;case(4,encode(mul(d)),be(0),be(r)+be(s),expected=b'\1')
 case(4,encode((G[0],(-G[1])%P)),be(1),be(1)+be(1),expected=b'\0')
 # Both u1*G and u2*Q equal G, challenging the equal-add fallback.
 r=mul(2)[0]%N;case(4,encode(G),be(r),be(r)+be(r),expected=b'\1')
 x=N+1
 while True:
  rhs=(pow(x,3,P)-3*x+B)%P;y=pow(rhs,(P+1)//4,P)
  if y*y%P==rhs:break
  x+=1
 point=(x,y);r=x-N;q=mul(pow(r,-1,N),add(point,(G[0],(-G[1])%P)))
 case(4,encode(q),be(1),be(r)+be(1),expected=b'\1')
 # Valid x=0 peer: ECDH's x output is allowed to be all zero.
 y=pow(B,(P+1)//4,P);assert y*y%P==B
 for key in [encode((0,y)),encode((0,y),True)]:case(3,be(1),key,expected=b'\0'*32)
 # OpenSSL is a separate byte oracle for public keys/ECDH, and verifies
 # independently model-generated deterministic signatures.
 spki_prefix=bytes.fromhex('3059301306072a8648ce3d020106082a8648ce3d030107034200')
 def call(args):return subprocess.run(['openssl',*args],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10).stdout
 with tempfile.TemporaryDirectory() as directory:
  tmp=pathlib.Path(directory)
  for i,d in enumerate(scalars[-6:]):
   sec1=b'\x30\x31\x02\x01\x01\x04\x20'+be(d)+bytes.fromhex('a00a06082a8648ce3d030107');(tmp/'private.der').write_bytes(sec1)
   public=call(['pkey','-inform','DER','-in',str(tmp/'private.der'),'-pubout','-outform','DER']);assert public.startswith(spki_prefix) and len(public)==len(spki_prefix)+65;q=public[len(spki_prefix):];case(0,be(d),expected=q)
   peer=encode(mul(scalars[i]));(tmp/'peer.der').write_bytes(spki_prefix+peer);secret=call(['pkeyutl','-derive','-inkey',str(tmp/'private.der'),'-keyform','DER','-peerkey',str(tmp/'peer.der'),'-peerform','DER']);assert len(secret)==32;case(3,be(d),peer,expected=secret)
   msg=b'P256 independent OpenSSL '+bytes([i]);sig=sign_model(d,msg,17+i);(tmp/'message').write_bytes(msg);(tmp/'public.der').write_bytes(public);(tmp/'signature.der').write_bytes(der(int.from_bytes(sig[:32],'big'),int.from_bytes(sig[32:],'big')))
   assert b'Verified OK' in call(['dgst','-sha256','-verify',str(tmp/'public.der'),'-keyform','DER','-signature',str(tmp/'signature.der'),str(tmp/'message')]);case(5,q,msg,sig,expected=b'\1')

def mutations():
 digest=hashlib.sha256(b'sample').digest()
 for source,op,slot in [(RFC_Q,4,0),(digest,4,1),(RFC_SIG,4,2),(b'sample',5,1)]:
  for i in range(len(source)):
   changed=bytearray(source);changed[i]^=1;a=RFC_Q;b=digest if op==4 else b'sample';c=RFC_SIG
   if slot==0:a=bytes(changed)
   elif slot==1:b=bytes(changed)
   else:c=bytes(changed)
   case(op,a,b,c)
 # Accept high/low-s pair as ordinary ECDSA, without an unsolicited low-S policy.
 r=int.from_bytes(RFC_SIG[:32],'big');s=int.from_bytes(RFC_SIG[32:],'big')
 for value in (s,N-s):case(4,RFC_Q,digest,be(r)+be(value),expected=b'\1')
 for r,s in [(0,1),(1,0),(N,1),(1,N),((1<<256)-1,1),(1,(1<<256)-1)]:case(4,RFC_Q,digest,be(r)+be(s),expected=b'\0')

def invalid():
 for d in [b'',b'\0'*31,b'\0'*33,be(0),be(N),be(N+1),be((1<<256)-1)]:case(0,d);case(3,d,RFC_Q)
 bad=[b'',b'\0',RFC_Q[:-1],RFC_Q+b'x',b'\0'+RFC_Q[1:],b'\x06'+RFC_Q[1:],b'\x07'+RFC_Q[1:],b'\x04'+be(P)+RFC_Q[33:],b'\x04'+RFC_Q[1:33]+be(P),b'\x04'+be(0)+be(0),b'\x02'+be(P),b'\x03'+be(P)]
 x=0
 while pow((pow(x,3,P)-3*x+B)%P,(P-1)//2,P)!=P-1:x+=1
 bad+=[b'\x02'+be(x),b'\x03'+be(x)]
 for q in bad:case(1,q);case(2,q);case(3,be(1),q);case(4,q,hashlib.sha256(b'sample').digest(),RFC_SIG)
 for mode in (1,2,3):
  for op,a,b,c in [(0,be(1),b'',b''),(1,RFC_Q,b'',b''),(2,RFC_Q,b'',b''),(3,b'',b'',b''),(4,b'',b'',b''),(5,b'',b'',b''),(6,b'',b'',b'')]:case(op,a,b,c,mode=mode)
 for mode in (4,5):
  for op in (3,4,5):case(op,b'',b'',b'',mode=mode)
 for digest in (b'',b'x'*31,b'x'*33):case(4,RFC_Q,digest,RFC_SIG)
 for sig in (b'',b'x'*63,b'x'*65):case(4,RFC_Q,b'x'*32,sig);case(5,RFC_Q,b'm',sig)
 good=der(int.from_bytes(RFC_SIG[:32],'big'),int.from_bytes(RFC_SIG[32:],'big'))
 for raw in [good,der(1,1),der(N,N),der(128,255),b'',good[:-1],good+b'\0',b'\x30\x80'+good[2:]+b'\0\0',b'\x30\x81'+bytes([len(good)-2])+good[2:],b'\x30\x06\x02\x01\0\x02\x01\1',b'\x30\x06\x02\x01\x80\x02\x01\1',b'\x30\x07\x02\x02\0\1\x02\x01\1',b'\x30\x06\x02\0\x02\x02\0\1',b'\x30\x27\x02\x22'+b'\1'*34+b'\x02\x01\1']:
  case(6,raw)

MODES={'published':published,'model':openssl_and_model,'mutations':mutations,'invalid':invalid}
def main():
 MODES[sys.argv[1]]();out=sys.stdout.buffer;out.write(struct.pack('<Q',len(CASES)))
 for wire,result in CASES:out.write(struct.pack('<Q',len(wire))+wire+struct.pack('<Q',len(result))+struct.pack('<'+'Q'*len(result),*result))
if __name__=='__main__':main()
