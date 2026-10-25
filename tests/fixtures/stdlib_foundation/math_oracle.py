"""450-decimal-digit, exact-input-bit oracle. Production runs native Lanius.

Reference work stays in this test. The seed and raw input/output bits are
reported on any discrepancy. 450 digits exceed the 309 decimal digits of
MAX finite binary64 plus its 53 significand bits and a wide error margin.
"""
import math,random,struct,subprocess,sys,time
from pathlib import Path
import mpmath as mp
mp.mp.dps=450
MASK=(1<<64)-1; SIGN=1<<63; INF=0x7ff0000000000000
OPS={'sin':0,'cos':1,'sin_cos':2,'exp':3,'expm1':4,'log':5,'log1p':6,'atan':7,'atan2':8,'pow':9,'scalbn':10}
rng=random.Random(0x6d6174682026)
def bits(x):return struct.unpack('<Q',struct.pack('<d',x))[0]
def value(x):return struct.unpack('<d',struct.pack('<Q',x))[0]
def exact(raw):
    sign=-1 if raw&SIGN else 1;e=(raw>>52)&2047;m=raw&((1<<52)-1)
    assert e!=2047
    if e:m|=1<<52;e-=1075
    else:e=-1074
    return sign*mp.ldexp(mp.mpf(m),e)
def ordered(raw):return (~raw&MASK) if raw&SIGN else raw|SIGN
def rounded(x):
    try:return bits(float(x))
    except OverflowError:return INF|(SIGN if x<0 else 0)
cases=[]
def add(op,x,y=0,n=0,raw=False,published=None):
    cases.append((op,n,x if raw else bits(x),y if raw else bits(y),published))
def around(x,count=2):
    b=bits(x)
    return [value(b+i) for i in range(-count,count+1) if 0<=b+i<=MASK and math.isfinite(value(b+i))]
# Every binary64 exponent, both signs, selected subnormals and near maximal values.
trig=[0.0,-0.0,value(1),value(SIGN|1),value(0x000fffffffffffff),value(0x0010000000000000),value(0x7fefffffffffffff)]
for e in range(1,2047):
    raw=(e<<52)|rng.getrandbits(52);trig += [value(raw),value(raw|SIGN)]
for center in [math.pi/4,math.pi/2,math.pi,3*math.pi/2,2*math.pi,2**20*math.pi/2,2**-27,2**-28]:
    trig+=around(center,5)+around(-center,5)
for k in [1,2,3,4,7,16,31,127,1024,2**15,2**19,2**20,2**30,2**52,2**100,2**500,2**1000]:
    center=float(mp.pi*k/2);trig+=around(center,3)+around(-center,3)
for x in trig:add(2,x)
# The public scalar wrappers must agree bit-for-bit with paired evaluation.
for x in trig[::37]:add(0,x);add(1,x)
# Exponentials across their reduced interval, cancellation and overflow/subnormal thresholds.
exp_points=[rng.uniform(-750,710) for _ in range(700)]
for k in range(-1075,1025,3):exp_points+=around(float(mp.log(2)*k),1)
for center in [0.,-0.,2**-54,-2**-54,2**-28,-2**-28,math.log(2)/2,-math.log(2)/2,math.log(2),-math.log(2),56*math.log(2),-56*math.log(2),709.782712893384,-745.1332191019411,-708.3964185322641]:exp_points+=around(center,3)
for x in exp_points:add(3,x);add(4,x)
# Logs cover every exponent and normalization / near-one branches.
for e in range(2047):
    raw=(e<<52)|rng.getrandbits(52)
    if raw:add(5,raw,raw=True)
for center in [value(1),value(0x000fffffffffffff),value(0x0010000000000000),0.5,1.,1.5,2.,math.sqrt(0.5),math.sqrt(2),value(0x7fefffffffffffff)]:
    for x in around(center,7):
        if x>0:add(5,x)
for _ in range(700):add(6,rng.uniform(-.99999999999999,100))
for center in [-1.,-0.5,0.,2**-54,-2**-54,2**-29,-2**-29,math.sqrt(.5)-1,math.sqrt(2)-1,2**53]:
    for x in around(center,6):
        if x>-1:add(6,x)
for e in range(1,2047,3):add(6,value((e<<52)|rng.getrandbits(52)))
# atan range transforms and atan2 signs, zeros and exponent-ratio extremes.
for x in trig[::3]:add(7,x)
for center in [0.,.4375,.6875,1.,1.1875,2.4375,2**66]:
    for x in around(center,5):add(7,x);add(7,-x)
for _ in range(1200):
    a=rng.getrandbits(64);b=rng.getrandbits(64)
    if (a>>52)&2047!=2047 and (b>>52)&2047!=2047:add(8,a,b,raw=True)
for a in [value(1),value(0x0010000000000000),1.,value(0x7fefffffffffffff)]:
    for b in [value(1),value(0x0010000000000000),1.,value(0x7fefffffffffffff)]:
        for s in [1.,-1.]:
            for t in [1.,-1.]:add(8,s*a,t*b)
# Pow: near one with enormous exponents, log2 interval boundaries, integer signs,
# exact powers of two, overflow/subnormal transitions, full-range positive bases.
for x in [value(1),value(0x000fffffffffffff),value(0x0010000000000000),.5,.75,1.,1.5,2.,3.,10.,value(0x7fefffffffffffff)]:
    for y in [-1075.,-1074.,-1024.,-65.,-64.,-63.,-3.,-2.,-1.,-.5,0.,.5,1.,2.,3.,4.,31.,32.,63.,64.,65.,1023.,1024.]:add(9,x,y)
for center in [1.,math.sqrt(1.5),math.sqrt(3),.5,2.]:
    for x in around(center,5):
        if x>0:
            for y in [-1e300,-2**64,-2**31,-3.,-.5,.5,3.,2**31,2**64,1e300]:add(9,x,float(y))
for _ in range(1200):
    raw=rng.randrange(1,INF);x=value(raw);y=rng.uniform(-10,10);add(9,x,y)
for x in [-.5,-.75,-1.,-1.5,-2.,-3.,-10.,-value(0x0010000000000000)]:
    for y in [-1075.,-1074.,-65.,-64.,-63.,-3.,-2.,-1.,0.,1.,2.,3.,4.,31.,32.,63.,64.,65.,1023.,1024.]:add(9,x,y)
# Scaling is exact except a single final rounding in subnormal output.
for _ in range(800):
    raw=rng.getrandbits(64)
    if (raw>>52)&2047!=2047:add(10,raw,n=rng.choice([-2147483648,-50001,-1075,-1074,-1023,-54,-1,0,1,54,1023,1074,50001,2147483647]),raw=True)
# Published MIT libc-test sanity vectors; compare their expected value as well
# as the independently computed high-precision value.
for line in Path(__file__).with_name('math_reference_vectors.txt').read_text().splitlines():
    if not line or line.startswith('#'):continue
    name,x,y,want=line.split();add(OPS[name],float.fromhex(x),float.fromhex(y),published=want)
def reference(op,n,xb,yb):
    x=exact(xb);y=exact(yb)
    if op in [0,1,2]:
        if op==0:return rounded(mp.sin(x)),0
        if op==1:return rounded(mp.cos(x)),0
        return rounded(mp.sin(x)),rounded(mp.cos(x))
    if op==3:return rounded(mp.exp(x)),0
    if op==4:return rounded(mp.expm1(x)),0
    if op==5:
        if x<0:return None,0
        return (INF|SIGN if x==0 else rounded(mp.log(x))),0
    if op==6:
        if x<-1:return None,0
        return (INF|SIGN if x==-1 else rounded(mp.log1p(x))),0
    if op==7:return rounded(mp.atan(x)),0
    if op==8:return rounded(mp.atan2(x,y)),0
    if op==9:
        if x<0 and y!=mp.floor(y):return None,0
        return rounded(mp.power(x,y)),0
    if op==10:
        if n>50000:return INF|(xb&SIGN),0
        if n<-50000:return xb&SIGN,0
        return rounded(mp.ldexp(x,n)),0
    raise AssertionError(op)
packet=struct.pack('<I',len(cases))+b''.join(struct.pack('<iiQQ',op,n,xb,yb) for op,n,xb,yb,_ in cases)
start=time.perf_counter();r=subprocess.run([sys.argv[1]],input=packet,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=25);native=time.perf_counter()-start
assert r.returncode==0,(r.returncode,r.stderr,len(r.stdout));assert not r.stderr,r.stderr
assert len(r.stdout)==len(cases)*16,(len(r.stdout),len(cases))
maxima={};counts={};failures=[]
for index,(c,actual) in enumerate(zip(cases,struct.iter_unpack('<QQ',r.stdout))):
    op,n,xb,yb,published=c
    want=reference(op,n,xb,yb)
    # Mathematical zero has no sign; use the API's signed-zero contract.
    if op in [0,2,4,6,7,10] and (xb&~SIGN)==0:want=(xb,want[1])
    if op==9 and actual[0]&~SIGN==0 and want[0]==0:
        if value(xb)<0 and value(yb).is_integer() and abs(value(yb))<2**53 and int(value(yb))%2:want=(SIGN,0)
    label=(f'seed=0x6d6174682026 case={index}',op,n,hex(xb),hex(yb),hex(actual[0]),str(want))
    for j,(got,target) in enumerate(zip(actual,want)):
        if target is None:
            if not math.isnan(value(got)):failures.append((label,j,'expected NaN'))
            continue
        if target&~SIGN>=INF:
            if got!=target:failures.append((label,j,'special mismatch'))
            continue
        if got&~SIGN>=INF:failures.append((label,j,'unexpected nonfinite'));continue
        error=abs(ordered(got)-ordered(target))
        if op==2 or j==0:
            maxima[op]=max(maxima.get(op,0),error);counts[op]=counts.get(op,0)+1
        tolerance=0 if op==10 else 4
        if error>tolerance:failures.append((label,j,error))
    if published:
        target=None if published=='nan' else bits(float.fromhex(published))
        if target is None:
            if not math.isnan(value(actual[0])):failures.append((label,'published NaN'))
        elif abs(ordered(actual[0])-ordered(target))>4:failures.append((label,'published mismatch',published))
assert not failures,('math discrepancies',len(failures),failures[:12])
print(f'{len(cases)} cases, 450 decimal digits, exact input-bit reconstruction; native process {native:.3f}s')
for op in sorted(maxima):print(next(k for k,v in OPS.items() if v==op),f'checked_values={counts[op]} max_observed_ULP={maxima[op]}')
