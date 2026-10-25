"""Independent direct DFT / Fraction convolution reference; test code only."""
import cmath, fractions, math, random, struct, subprocess, sys
F=fractions.Fraction
rng=random.Random(0x516a12026)
cases=[]
def add(op,x,m=0,flags=0,factor=1.,right=(),status=0,exact=False,analytic=None):
    cases.append(dict(op=op,x=x,m=m,flags=flags,factor=factor,right=right,status=status,exact=exact,analytic=analytic))
def window(n,kind,periodic):
    if n==1:return [1.]
    if n==0:return []
    d=n if periodic else n-1
    def coefficient(i):
        a=math.tau*i/d
        if kind==0:return 1.
        if kind==1:return .5-.5*math.cos(a)
        if kind==2:return .54-.46*math.cos(a)
        return .42-.5*math.cos(a)+.08*math.cos(2*a)
    return [max(0.,min(1.,coefficient(i))) for i in range(n)]
def dft(x,inverse=False):
    n=len(x)
    if not n:return []
    sign=1 if inverse else -1
    return [complex(math.fsum((v*cmath.exp(sign*1j*math.tau*j*k/n)).real for j,v in enumerate(x)),
                    math.fsum((v*cmath.exp(sign*1j*math.tau*j*k/n)).imag for j,v in enumerate(x)))/(n if inverse else 1) for k in range(n)]
for n in [0,1,2,4,8,16,32,64]:
    for direction in [0,1,6]:
        for _ in range(4):add(direction,[complex(rng.uniform(-2,2),rng.uniform(-2,2)) for _ in range(n)])
    if n:
        x=[0j]*n;x[0]=1;add(0,x,exact=True,analytic=[1+0j]*n)
        add(1,[1+0j]*n,exact=True,analytic=[1+0j]+[0j]*(n-1))
for n in [0,1,2,3,4,15,16,31]:
    for kind in range(4):
        for periodic in [False,True]:
            x=[rng.uniform(-3,3) for _ in range(n)];flags=kind+(16 if periodic else 0)
            add(3,x,flags=flags)
            size=0 if n==0 else 1<<(n-1).bit_length();add(2,x,m=size,flags=flags)
for _ in range(48):
    n=rng.randrange(25);m=rng.randrange(25)
    x=[rng.randrange(-7,8)/8 for _ in range(n)];y=[rng.randrange(-7,8)/8 for _ in range(m)]
    add(4,x,m=m,right=y,exact=True)
for _ in range(20):
    n=rng.randrange(1,40);m=rng.randrange(1,40)
    add(4,[rng.uniform(-1e6,1e6) for _ in range(n)],m=m,right=[rng.uniform(-1e-6,1e-6) for _ in range(m)])
add(4,[1e16,1.,-1e16],m=3,right=[1.,1.,1.],exact=True)
for factor in [0.,1.,.125]:add(5,[3+4j,0j,1e-150+2e-150j],factor=factor)
add(5,[complex(sys.float_info.max,sys.float_info.max)],factor=1e-200)
add(0,[complex(math.nan,0)],status=7);add(0,[1+0j]*3,status=3)
add(0,[complex(sys.float_info.max,0)]*2,status=8)
# The documented unscaled inverse can reject intermediate overflow.
add(1,[complex(sys.float_info.max,0)]*2,status=8)
add(4,[sys.float_info.max],m=1,right=[2.],status=8)
add(4,[math.inf],m=0,status=7);add(5,[1e200+0j],status=8)
add(5,[1+0j],factor=-1.,status=2)
add(2,[1.,2.,3.],m=2,status=3)
# Analytic scale vectors do not reuse an FFT implementation as their oracle.
n=8192;x=[0j]*n;x[0]=1;add(0,x,exact=True,analytic=[1+0j]*n)
add(6,x,analytic=x)
n=4096;k=37;x=[math.cos(math.tau*k*i/n) for i in range(n)];want=[0j]*n;want[k]=n/2;want[n-k]=n/2
add(2,x,m=n,analytic=want)
packet=bytearray()
for c in cases:
    packet+=struct.pack('<iiiid',c['op'],len(c['x']),c['m'],c['flags'],c['factor'])
    if c['op'] in [0,1,5,6]:packet+=b''.join(struct.pack('<dd',z.real,z.imag) for z in c['x'])
    else:packet+=b''.join(struct.pack('<d',z) for z in list(c['x'])+list(c['right']))
r=subprocess.run([sys.argv[1]],input=packet,capture_output=True,timeout=35)
assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr)
at=0
for index,c in enumerate(cases):
    status,n=struct.unpack_from('<ii',r.stdout,at);at+=8;label=('seed=0x516a12026',index,c['op'],len(c['x']),c['m'],c['flags'])
    assert status==c['status'],(label,status,c['status'])
    if status:assert n==0;continue
    stride=2 if c['op'] in [0,1,2,5,6] else 1
    raw=struct.unpack_from('<'+'d'*(n*stride),r.stdout,at);at+=n*stride*8
    if c['op'] in [0,1,2,6]:got=[complex(raw[i],raw[i+1]) for i in range(0,len(raw),2)]
    elif c['op']==5:got=[(raw[i],raw[i+1]) for i in range(0,len(raw),2)]
    else:got=raw
    x=c['x'];scale=1.
    if c['analytic'] is not None:want=c['analytic'];scale=max(1.,sum(map(abs,x)))
    elif c['op'] in [0,1]:want=dft(x,c['op']==1);scale=max(1.,sum(map(abs,x)))/(len(x) if c['op']==1 and x else 1)
    elif c['op']==6:want=x;scale=max(1.,sum(map(abs,x)))
    elif c['op'] in [2,3]:
        weights=window(len(x),c['flags']%16,c['flags']>=16);values=[v*w for v,w in zip(x,weights)]
        want=dft(values+[0j]*(c['m']-len(values))) if c['op']==2 else values
        scale=max(1.,sum(map(abs,values)))
    elif c['op']==4:
        y=c['right'];want=[];scales=[]
        for j in range(len(x)+len(y)-1 if x and y else 0):
            products=[F.from_float(x[i])*F.from_float(y[j-i]) for i in range(len(x)) if 0<=j-i<len(y)]
            want.append(float(sum(products,F(0))));scales.append(max(1.,float(sum(map(abs,products),F(0)))))
    else:
        want=[]
        for z in x:
            z=z*c['factor'];want.append((math.hypot(z.real,z.imag),float(F.from_float(z.real)**2+F.from_float(z.imag)**2)))
    assert n==len(want),(label,n,len(want))
    for j,(a,b) in enumerate(zip(got,want)):
        if c['exact']:assert a==b,(label,j,a,b);continue
        if c['op']==5:
            for part,(v,w) in enumerate(zip(a,b)):assert math.isfinite(v) and abs(v-w)<=max(8*math.ulp(w),3e-14*abs(w)),(label,j,part,v,w)
        else:
            tolerance=3e-12*(scales[j] if c['op']==4 else scale)
            assert math.isfinite(abs(a)) and abs(a-b)<=tolerance,(label,j,a,b,tolerance)
    if c['op']==2 and n:
        norm=max(1.,sum(map(abs,x)))
        for j in range(1,n):assert abs(got[j]-got[n-j].conjugate())<=3e-12*norm,(label,'real symmetry',j)
assert at==len(r.stdout),(at,len(r.stdout))
print('signal independent DFT/Fraction/window/scale cases',len(cases))
