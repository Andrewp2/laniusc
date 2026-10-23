"""Independent arbitrary-precision oracle for the native integer driver."""
import random,struct,subprocess,sys,time
from pathlib import Path
MASK=(1<<64)-1
limits=[(-(1<<(n-1)),(1<<(n-1))-1,n,True) if signed else (0,(1<<n)-1,n,False) for n,signed in [(8,1),(8,0),(16,1),(16,0),(32,1),(32,0),(64,1),(64,0),(64,1),(64,0)]]
def cast(a,n=64,signed=False):
 a&=(1<<n)-1
 return a-(1<<n) if signed and a&(1<<(n-1)) else a
def bound(a,lo,hi):return a if lo<=a<=hi else None
def ref(kind,op,raw_a,raw_b,n):
 signed=kind%2==0;lo,hi,width,_=limits[6 if signed else 7]
 a=cast(raw_a,64,signed);b=cast(raw_b,64,signed)
 clamp=lambda x:max(lo,min(hi,x))
 if op>=52:
  offset=op-52;to=offset<30;other=(offset%30)//3;mode=offset%3
  ol,oh,ow,os=limits[other]
  number=a if to else cast(raw_a,ow,os)
  low,high,w,s=(ol,oh,ow,os) if to else (lo,hi,width,signed)
  return bound(number,low,high) if mode==0 else (max(low,min(high,number)) if mode==1 else cast(number,w,s))
 if op in [0,1,2,3,4,5,6,7,8]:
  v=[lambda:a+b,lambda:a-b,lambda:a*b][op%3]()
  return cast(v,64,signed) if op<3 else (bound(v,lo,hi) if op<6 else clamp(v))
 if op in [9,10,11,12,48,49,50]:
  if b==0:return None
  if signed and a==lo and b==-1:
   return lo if op==48 else (0 if op==49 else (hi if op==50 else None))
  q=abs(a)//abs(b)*(-1 if (a<0)!=(b<0) else 1);r=a-q*b
  if op in [11,12] and r<0:q+=-1 if b>0 else 1;r=a-q*b
  return r if op in [10,12,49] else q
 if op==13:return bound(-a,lo,hi)
 if op==14:return cast(-a,64,signed)
 if op==15:return clamp(-a)
 if op in [16,17,18]:
  if op==17:return cast(pow(a,n,1<<64),64,signed)
  if abs(a)>1 and n>=64:return None if op==16 else (lo if a<0 and n%2 else hi)
  v=pow(a,n)
  return bound(v,lo,hi) if op==16 else clamp(v)
 if op in [19,20,21,22]:
  if op<21 and n>=64:return None
  n%=64;return cast(a<<n,64,signed) if op in [19,21] else a>>n
 if op in [23,24]:
  n%=64;v=raw_a
  if op==24:n=(-n)%64
  return cast((v<<n)|(v>>((64-n)%64)),64,signed)
 if op==25:return cast(int(f'{raw_a:064b}'[::-1],2),64,signed)
 if op==26:return cast(int.from_bytes(raw_a.to_bytes(8,'little'),'big'),64,signed)
 if op==27:return raw_a.bit_count()
 if op==28:return 64-raw_a.bit_count()
 if op in [29,31]:return 64-(raw_a if op==29 else raw_a^MASK).bit_length()
 if op in [30,32]:
  x=raw_a if op==30 else raw_a^MASK;return (x&-x).bit_length()-1 if x else 64
 if op==33:return bound(1 if a<=1 else 1<<(a-1).bit_length(),lo,hi)
 if op==34:return bound(abs(a),lo,hi)
 if op==35:return cast(abs(a),64,signed)
 if op==36:return clamp(abs(a))
 if op==37:return (a>0)-(a<0)
 if op==38:return abs(a)
 if op==39:return abs(a-b)
 if op==40:return min(a,b)
 if op==41:return max(a,b)
 if op==42:return int(a%2==0)
 if op==43:return int(b!=0 and a%b==0)
 if op==44:return bound(a,-(1<<31),(1<<31)-1)
 if op==45:return bound(a,0,(1<<32)-1)
 if op==46:return bound(cast(raw_a,64,True),lo,hi)
 if op==47:return bound(raw_a,lo,hi)
 if op==51:return int(a>0 and a&(a-1)==0)
 raise ValueError(op)
edges=[0,1,2,3,63,64,127,128,255,256,32767,32768,65535,65536,(1<<31)-1,1<<31,(1<<32)-1,1<<32,(1<<32)+1,(1<<62)-1,1<<62,(1<<62)+1,(1<<63)-2,(1<<63)-1,1<<63,(1<<63)+1,MASK-1,MASK]
shifts=[0,1,2,7,31,32,33,62,63,64,65,127,128,129,(1<<32)-1]
rng=random.Random(0x16402026)
cases=[]
def push(k,op,a,b,n):
 if k%2 and op in [15,34,35,36,37,38]:return
 if op in [48,49,50] and b==0:return
 cases.append((k,op,a,b,n))
for k in range(4):
 for op in range(112):
  for i in range(64):push(k,op,edges[i] if i<len(edges) else rng.getrandbits(64),edges[(i*11+7)%len(edges)] if i<len(edges) else rng.getrandbits(64),shifts[i%len(shifts)])
 for op in [0,1,2,3,4,5,6,7,8,9,10,11,12,39,43,48,49,50]:
  for a in edges:
   for b in edges:push(k,op,a,b,3)
# Signed non-power-of-two multiplication thresholds: fit and overflow,
# both signs and operand orders, across fixed and pointer-width modules.
for k in (0,2):
 for small in (-3,3):
  for large in (-3074457345618258602,-3074457345618258603,3074457345618258602,3074457345618258603):
   for a,b in ((small,large),(large,small)):
    for op in (2,5,8):push(k,op,a&MASK,b&MASK,0)
data=struct.pack('<I',len(cases))+b''.join(struct.pack('<BB2xQQI',*c) for c in cases)
started=time.perf_counter()
result=subprocess.run([sys.argv[1]],input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
elapsed=time.perf_counter()-started
assert result.returncode==0,(result.returncode,result.stderr)
assert len(result.stdout)==12*len(cases),(len(result.stdout),len(cases))
for i,(c,actual) in enumerate(zip(cases,struct.iter_unpack('<IQ',result.stdout))):
 expected=ref(*c);wanted=(int(expected is not None),0 if expected is None else expected&MASK)
 if actual!=wanted:raise AssertionError((i,c,actual,wanted))
print(f'{len(cases):,} native arithmetic/bit/conversion cases match Python arbitrary-precision reference, seed=0x16402026; native process {elapsed:.6f}s')
