#!/usr/bin/env python3
"""Independent HMAC/hashlib + HKDF recurrence and actual OpenSSL byte checks."""
import hashlib,hmac,random,struct,subprocess,sys
hm=lambda key,msg:hmac.new(key,msg,hashlib.sha384).digest()
MAX=12240
HI=(1<<61)-1
LO=(1<<64)-1
CASES=[]
def digest(value):return [0,48,*value,*([0]*16)]
def expand(prk,info,n):
 result=bytearray();previous=b''
 for block in range(1,(n+47)//48+1):
  previous=hm(prk,previous+info+bytes([block]));result.extend(previous)
 return bytes(result[:n])
def answer(op,mode,param,n,a,b,c):
 if op==6:
  if mode in (1,2,3):return [1,0]
  return digest(hm(a,b''))
 if op==0:
  if mode in (1,2,3,4,5):return [1,0]
  return digest(hm(a,b))
 if op==1:
  value=hm(a,b);changed=bytearray(value+b'\0'*16);changed[0]^=128;changed[63]^=1
  return digest(value)+digest(value)+[3,0,1,0]+digest(hm(a,b[:len(b)//2]+c))+digest(hm(a,b''))+digest(value)+digest(hm(c,b))+digest(value)+[0,48,*changed]
 if op==2:
  if mode in (1,2,3,4,5):return [11,0]
  return digest(hm(a,b))
 if op in (3,4):
  code=0;value=b''
  if mode in (1,2,3,4,5,7,8,9) or (mode==6 and op==4):code=11
  elif op==3 and len(a)<48:code=12
  elif n>MAX:code=13
  else:value=expand(a,b,n) if op==3 else expand(hm(a,b),c,n)
  out=bytearray(b'\xa5'*12256)
  if not code:out[5:5+n]=value
  return [code,0 if code else n,*struct.unpack('<1532Q',out)]
 if op==5:
  counters=[(2,0,0,LO,HI,127),(0,1,1,0,1,0),(2,0,0,0,HI+1,0),(0,1,1,0,HI,0),(2,0,1,LO,HI,127),(1,0,0,LO,HI,127),(3,0,0,LO,HI,127)][param]
  return list(counters)+digest(hm(a,b))
 raise ValueError(op)
def case(op,a=b'',b=b'',c=b'',n=0,param=0,mode=0,layouts=(0,1)):
 assert max(len(a),len(b),len(c))<=1024 and n<=12241
 for layout in layouts:
  wire=struct.pack('<8Q',op,layout,mode,param,n,len(a),len(b),len(c))+a+b+c;CASES.append((wire,answer(op,mode,param,n,a,b,c)))
RFC=[
 (b'\x0b'*20,b'Hi There','afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59cfaea9ea9076ede7f4af152e8b2fa9cb6'),
 (b'Jefe',b'what do ya want for nothing?','af45d2e376484031617f78d2b58a6b1b9c7ef464f5a01b47e42ec3736322445e8e2240ca5e69e2c78b3239ecfab21649'),
 (b'\xaa'*20,b'\xdd'*50,'88062608d3e6ad8a0aa2ace014c8a86f0aa635d947ac9febe83ef4e55966144b2a5ab39dc13814b94e3ab6e101a34f27'),
 (bytes(range(1,26)),b'\xcd'*50,'3e8a69b7783c25851933ab6290af6ca77a9981480850009cc5577c6e1f573b4e6801dd23c4a7d679ccf8a386c674cffb'),
 (b'\x0c'*20,b'Test With Truncation','3abf34c3503b2a23a46efc619baef897'),
 (b'\xaa'*131,b'Test Using Larger Than Block-Size Key - Hash Key First','4ece084485813e9088d2c63a041bc5b44f9ef1012a2b588f3cd11f05033ac4c60c2ef6ab4030fe8296248df163f44952'),
 (b'\xaa'*131,b'This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.','6617178e941f020d351e2f254e8fd32c602420feb0b8fb9adccebb82461e99c5a678cc31e799176d3860e6110c46523e')]
def call(args,data=None):
 result=subprocess.run(['openssl',*args],input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
 assert result.returncode==0,(args,result.returncode,result.stderr)
 return result.stdout

def vectors():
 for i,(key,msg,hexout) in enumerate(RFC):
  expected=bytes.fromhex(hexout);actual=hm(key,msg);assert actual.startswith(expected)
  if i!=4:assert len(expected)==48 and actual==expected
  else:assert len(expected)==16 and actual==call(['dgst','-sha384','-mac','HMAC','-macopt','hexkey:'+key.hex(),'-binary'],msg)
  case(0,key,msg)
  for chunk in (1,7,127,128,129):case(1,key,msg,b'fork continuation',param=chunk)
 # Independent key/block boundaries; deterministic random bytes avoid
 # relying solely on repeated RFC patterns.
 rng=random.Random(0x3844231)
 for kn in (0,1,47,48,127,128,129,131,255):
  case(6,rng.randbytes(kn))
  for mn in (0,1,111,112,127,128,129,255,256):
   key=rng.randbytes(kn);msg=rng.randbytes(mn);case(0,key,msg);case(1,key,msg,rng.randbytes(17),param=[1,7,127,128,129][(kn+mn)%5])

def kdf():
 rng=random.Random(0x3845869)
 for size in (0,1,47,48,49,95,96,97,255,256,257,1024,12239,12240):
  for empty in (False,True):
   salt=b'' if empty else rng.randbytes(17);ikm=b'' if empty else rng.randbytes(129);info=b'' if empty else rng.randbytes(31);prk=hm(salt,ikm)
   case(2,salt,ikm);case(3,prk,info,n=size);case(4,salt,ikm,info,n=size)
 for salt in (b'',b'\0'*48):case(2,salt,b'explicit empty-salt equivalence')
 for pn in (48,49,127,128,129,131):
  for infon in (0,1,111,112,127,128,129,255,256):case(3,rng.randbytes(pn),rng.randbytes(infon),n=97)
 # Actual OpenSSL comparisons including counter255. Inputs are nonempty so
 # CLI parameter parsing does not conflate an omitted option with empty bytes.
 for i,size in enumerate((1,48,49,97,255,12240)):
  salt=rng.randbytes(13+i);ikm=rng.randbytes(31+i);info=rng.randbytes(7+i);expected=expand(hm(salt,ikm),info,size)
  actual=call(['kdf','-binary','-keylen',str(size),'-digest','SHA384','-kdfopt','hexkey:'+ikm.hex(),'-kdfopt','hexsalt:'+salt.hex(),'-kdfopt','hexinfo:'+info.hex(),'HKDF']);assert actual==expected
  case(4,salt,ikm,info,n=size)

def rejects_and_seams():
 for mode in (1,2,3):case(6,mode=mode)
 for op in (0,2):
  for mode in (1,2,3,4,5):case(op,b'',b'',mode=mode)
 for op in (3,4):
  for mode in range(1,10):
   for size in (0,12241):case(op,b'x'*47,b'ikm',b'info',n=size,mode=mode)
 for pn in (0,1,47,48):
  for size in (0,1,48,12240,12241):case(3,b'x'*pn,b'',n=size)
 for op in (3,4):case(op,b'x'*48,b'',b'',n=12241)
 for param in range(7):
  for kn in (0,127,128,129,131):case(5,bytes((i*29+7)%256 for i in range(kn)),b'counter-seam reset',param=param)

MODES={'hmac':vectors,'hkdf':kdf,'limits':rejects_and_seams}
def main():
 MODES[sys.argv[1]]();out=sys.stdout.buffer;out.write(struct.pack('<Q',len(CASES)))
 for wire,expected in CASES:out.write(struct.pack('<Q',len(wire))+wire+struct.pack('<Q',len(expected))+struct.pack('<'+'Q'*len(expected),*expected))
if __name__=='__main__':main()
