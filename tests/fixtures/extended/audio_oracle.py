import decimal, fractions, itertools, math, random, struct, subprocess, sys
D=decimal.Decimal
F=fractions.Fraction
def exact_mean(x):
    return float(sum(map(F.from_float,x),F(0))/len(x))
def packed_bits(x):return struct.pack("<d",x)
def same(a,b,label):assert packed_bits(a)==packed_bits(b),(label,a,b,packed_bits(a).hex(),packed_bits(b).hex())
decimal.getcontext().prec=2500
rng=random.Random(0xa0d1026)
cases=[]
def add(op,x,channels=1,factor=1,y=None):
    if y is None:y=[0.]*len(x)
    cases.append((op,x,channels,factor,y))
for channels in [1,2,3,6,17]:
    for frames in [0,1,2,7,31,127]:
        x=[rng.uniform(-3,3) for _ in range(channels*frames)]
        y=[rng.uniform(-2,2) for _ in x]
        for op in range(5):add(op,x,channels,rng.choice([0.,-.5,1.,3.]),y)
for x in [[0.,-0.],[math.ulp(0.)]*9,[3e-300,-4e-300]*9,[3e300,-4e300]*9,[sys.float_info.max]*9,[sys.float_info.max,-sys.float_info.max]*4,[1e16,1.,-1e16],[-1.,1.,0.]]:
    add(0,x)
    add(3,x,len(x))
add(1,[1.,sys.float_info.max],factor=2.)
for op in [1,2,4]:
    for factor in [math.nan,math.inf,-math.inf]:add(op,[1.,2.],factor=factor)
for x in [[1.,math.nan],[math.inf],[-math.inf]]:add(0,x)
add(2,[1.,2.],factor=-1.)
add(4,[sys.float_info.max,1.],factor=2.,y=[sys.float_info.max,1.])
for _ in range(20):
    ch=rng.choice([1,2,8]);x=[rng.uniform(-1,1) for _ in range(ch*1000)]
    add(rng.randrange(5),x,ch,rng.uniform(-3,3),[rng.uniform(-1,1) for _ in x])
# Exact-input means: cancellation across the entire binary64 exponent range,
# permutations, sums exceeding f64, and ties around subnormal/normal boundaries.
def mean_cases(x):
    add(0,x)
    add(3,x,len(x))
for small in [math.ulp(0.),-math.ulp(0.),1e-300,-1e-300,1.,-1.]:
    for x in itertools.permutations([sys.float_info.max,small,-sys.float_info.max]):mean_cases(list(x))
for x in [[sys.float_info.max]*8192,[-sys.float_info.max]*8192,
          [sys.float_info.max]*200+[1e-300]*7+[-sys.float_info.max]*200,
          [math.ulp(0.)]*8192,[sys.float_info.max,-sys.float_info.max,0.,-0.],[-0.],[-0.,-0.]]:
    mean_cases(x)
def value(bits):return struct.unpack('<d',struct.pack('<Q',bits))[0]
for bits in [0,1,2,3,(1<<52)-2,(1<<52)-1,1<<52,(1<<52)+1,
             (2<<52)-1,(1023<<52)-1,1023<<52,(1023<<52)+1,
             (2046<<52),0x7feffffffffffffd,0x7feffffffffffffe]:
    a=value(bits);b=value(bits+1)
    for sign in [1,-1]:mean_cases([sign*a,sign*b])
for small in [math.ulp(0.),-math.ulp(0.),1e-300,-1e-300,0.]:
    mean_cases([1.,math.nextafter(1.,math.inf),0.,small])
for _ in range(140):
    x=[]
    for _ in range(rng.randrange(1,25)):
        bits=(rng.randrange(2047)<<52)|rng.getrandbits(52)
        a=value(bits);x.extend([a,-a])
    residual=[value((rng.randrange(2047)<<52)|rng.getrandbits(52))*rng.choice([-1,1]) for _ in range(rng.randrange(1,8))]
    x+=residual;rng.shuffle(x);mean_cases(x)
# Interleaved channels exercise exact DC with a non-unit physical sample step.
x=[sys.float_info.max,1e-300,-sys.float_info.max]*11
add(0,[v for pair in zip(x,reversed(x)) for v in pair],2)
packet=bytearray()
for op,x,ch,factor,y in cases:
    packet+=struct.pack('<iiiId',op,len(x),ch,48000,factor)
    packet+=b''.join(struct.pack('<dd',a,b) for a,b in zip(x,y))
r=subprocess.run([sys.argv[1]],input=packet,capture_output=True,timeout=30)
assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr)
at=0
def close(a,b,label):
    assert math.isfinite(a) and abs(a-b)<=max(8*math.ulp(b),5e-14*abs(b)),(label,a,b)
for idx,(op,x,ch,factor,y) in enumerate(cases):
    status,outch,n=struct.unpack_from('<iii',r.stdout,at);at+=12
    label=('seed=0xa0d1026',idx,op,ch,factor)
    if any(not math.isfinite(a) for a in x):assert status==4 and n==0,label;continue
    got=list(struct.unpack_from('<'+'d'*n,r.stdout,at));at+=8*n
    metrics=struct.unpack_from('<'+'d'*(outch*3),r.stdout,at);at+=24*outch
    want=x[:];error=0
    if op in [1,2,4] and not math.isfinite(factor):error=4
    elif op==1:
        want=[a*factor for a in x]
        if any(not math.isfinite(a) for a in want):error=5
    elif op==2:
        if factor<0:error=2
        else:want=[max(-factor,min(factor,a)) for a in x]
    elif op==3:
        want=[exact_mean(x[i:i+ch]) for i in range(0,len(x),ch)]
    elif op==4:
        want=[a+b*factor for a,b in zip(x,y)]
        if any(not math.isfinite(a) for a in want):error=5
    assert status==error,(label,status,error)
    if error:want=x
    assert n==len(want) and outch==(1 if op==3 and not error else ch),(label,n,outch)
    for i,(a,b) in enumerate(zip(got,want)):
        if op==3 and not error:same(a,b,(label,'exact mono',i))
        else:close(a,b,(label,'sample',i))
    frames=n//outch
    for c in range(outch):
        peak,rms,dc=metrics[c*3:c*3+3]
        if not frames:assert (peak,rms,dc)==(-1.,-1.,-1.);continue
        vals=got[c::outch];ds=[D.from_float(a) for a in vals]
        close(peak,max(map(abs,vals)),(label,'peak',c))
        close(rms,float((sum((a*a for a in ds),D(0))/frames).sqrt()),(label,'rms',c))
        expected=exact_mean(vals)
        same(float(sum(ds,D(0))/frames),expected,(label,'Decimal/Fraction mean oracle',c))
        same(dc,expected,(label,'exact dc',c))
assert at==len(r.stdout),(at,len(r.stdout))
print('verified',len(cases),'audio operations; exact Fraction/Decimal means and independent RMS metrics')
