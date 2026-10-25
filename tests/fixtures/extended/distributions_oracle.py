"""Exact binary64 inputs and 100–450 digit mpmath references.
Only this test driver uses Python; every reported value is native Lanius.
"""
import functools, math, random, struct, subprocess, sys, time
import mpmath as mp
mp.mp.dps=100
SEED=0x44535432303236
rng=random.Random(SEED)
cases=[]
def add(op,kind,a,b,x,n=1,seed=SEED,draws=10000000,work=10000000,status=0):
    cases.append((op,kind,n,seed,float(a),float(b),float(x),draws,work,status))
def adjacent(x):
    return [math.nextafter(x,-math.inf),x,math.nextafter(x,math.inf)]
for mean,sd in [(0.,1.),(-3.,.125),(1e300,1e299),(1e-300,1e-301)]:
    for z in [-math.inf,-40.,-38.5,-20.,-10.,-8.,-3.,-1.,0.,1.,3.,8.,10.,20.,38.5,40.,math.inf]:
        x=mean+sd*z
        for op in range(3):add(op,0,mean,sd,x)
for rate in [1e-300,1e-10,.1,1.,3.,1e10,1e300]:
    for t in [0.,1e-300,1e-15,.001,.1,1.,10.,100.,700.,750.,math.inf]:
        x=t/rate
        if math.isfinite(x) and x==0 and t:continue
        for op in range(3):add(op,1,rate,0,x)
for a in [1e-12,.01,.125,.5,1.,2.,7.99999999,8.,10.,100.,1000.]:
    points=[0.,1e-300,1e-20,1e-8,.1,.5,1.,2.,10.,100.,1000.,math.inf]
    points+= [a+d*math.sqrt(a) for d in [-10,-3,-1,0,1,3,10] if a+d*math.sqrt(a)>0]
    for scale in [.125,1.,10.]:
        for t in points:
            for op in range(3):add(op,2,a,scale,t*scale)
for a,b in [(.01,.01),(.01,10.),(.5,.5),(1.,1.),(1.,5.),(5.,1.),(2.,3.),(8.,8.),(8.,100.),(100.,8.),(100.,100.),(1000.,1000.)]:
    points=[0.,1e-300,1e-20,1e-8,.001,.1,.25,.5,.75,.9,.999,math.nextafter(1.,0.),1.]
    points+=adjacent(a/(a+b))
    for x in points:
        for op in range(3):add(op,3,a,b,x)
for _ in range(180):
    kind=rng.randrange(4);a=10**rng.uniform(-3,3);b=10**rng.uniform(-3,3)
    if kind==0:a=rng.uniform(-10,10);x=a+rng.uniform(-12,12)*b
    elif kind==1:x=10**rng.uniform(-10,3)/a
    elif kind==2:x=10**rng.uniform(-6,3)*b
    else:x=rng.random()
    for op in range(3):add(op,kind,a,b,x)
# Boundary/invalid contracts and explicit arithmetic/convergence failures.
for kind,a,b in [(0,0,0),(0,math.inf,1),(1,-1,0),(2,0,1),(3,1,math.nan)]:
    for op in range(4):add(op,kind,a,b,1,status=1)
for kind in range(4):add(2,kind,1,1,math.nan,status=2)
for kind in range(4):add(2,kind,1,1,.5,work=0,status=5)
add(2,2,1e20,1,1e20,status=4);add(2,3,1e20,2,.5,status=4)
add(2,2,1e6,1,1e6,work=5,status=5)
add(3,0,0,1,0,draws=0,status=6)
add(3,2,1,1,0,work=0,status=5)
# Deep tiny-shape gamma survival, extreme normal subtraction, scaled-coordinate
# overflow and true endpoint density limits.
for a in [1e-300,1e-100]:
    for x in [.1,.5,1.,2.,20.]:
        for op in range(3):add(op,2,a,1.,x)
for a,b in [(1e-12,.1),(1e-12,3.),(1e-100,10.),(1e-300,1000.),(.01,1e-12)]:
    for x in [1e-300,1e-20,.0001,.1,.5,.9,math.nextafter(1.,0.)]:
        for op in range(3):add(op,3,a,b,x)
for op in range(3):add(op,0,-sys.float_info.max,sys.float_info.max,sys.float_info.max)
for rate,x in [(1e-300,1e-300),(math.ulp(0.),math.ulp(0.)),(1e-200,1e-110)]:add(2,1,rate,0.,x)
for a in [math.ulp(0.),2*math.ulp(0.),8*math.ulp(0.),1e-308]:
    for x in [.1,.5,1.,2.]:add(2,2,a,1.,x)
    for b,x in [(1.,.9),(2.,.1)]:add(2,3,a,b,x)
    add(2,3,1.,a,.1)
for op in [0,1,2]:add(op,2,2.,1e-300,1e300,status=3)
# Exact symmetry is independent of normalization and remains valid when a+b
# overflows. These are intentionally tails-only analytic identity controls.
for a in [math.ulp(0.),1e-20,1e10,1e14,1e15,1e20,sys.float_info.max]:add(2,3,a,a,.5,work=1)

@functools.lru_cache(maxsize=None)
def mathematics(kind,a,b,x):
    # Precision follows cancellation in 1-x, not the exponent alone. Float
    # conversion retains its full53 input bits at every chosen precision.
    precision=450 if kind==3 and 0<x<1e-70 else 100
    with mp.workdps(precision):return mathematics_inner(kind,a,b,x)
def mathematics_inner(kind,a,b,x):
    a=mp.mpf(a);b=mp.mpf(b);x=mp.mpf(x)
    if kind==0:
        z=(x-a)/b;lp=-z*z/2-mp.log(b)-mp.log(2*mp.pi)/2
        p=mp.erfc(-z/mp.sqrt(2))/2;q=mp.erfc(z/mp.sqrt(2))/2
    elif kind==1:
        lp=mp.log(a)-a*x if x>=0 else mp.ninf
        p=-mp.expm1(-a*x) if x>0 else mp.mpf(0);q=mp.exp(-a*x) if x>0 else mp.mpf(1)
    elif kind==2:
        t=x/b
        if x==0:lp=mp.inf if a<1 else -mp.log(b) if a==1 else mp.ninf
        elif mp.isinf(x):lp=mp.ninf
        else:lp=(a-1)*mp.log(t)-t-mp.loggamma(a)-mp.log(b)
        if x<=0:p=mp.mpf(0);q=mp.mpf(1)
        elif mp.isinf(x):p=mp.mpf(1);q=mp.mpf(0)
        else:p=mp.gammainc(a,0,t,regularized=True);q=mp.gammainc(a,t,mp.inf,regularized=True)
    else:
        if x==0:lp=mp.inf if a<1 else mp.log(b) if a==1 else mp.ninf
        elif x==1:lp=mp.inf if b<1 else mp.log(a) if b==1 else mp.ninf
        else:lp=(a-1)*mp.log(x)+(b-1)*mp.log1p(-x)-mp.log(mp.beta(a,b))
        if x<=0:p=mp.mpf(0);q=mp.mpf(1)
        elif x>=1:p=mp.mpf(1);q=mp.mpf(0)
        else:p=mp.betainc(a,b,0,x,regularized=True);q=mp.betainc(b,a,0,1-x,regularized=True)
    if p<=q:return lp,p,1-p,mp.log(p),mp.log1p(-p)
    return lp,1-q,q,mp.log1p(-q),mp.log(q)
def reference(op,kind,a,b,x):
    if op==2 and kind==3 and a==b and x==.5:return [.5,.5,-math.log(2),-math.log(2)]
    lp,p,q,logp,logq=mathematics(kind,a,b,x)
    if op==0:return [float(lp)]
    if op==1:
        try:return [float(mp.exp(lp))]
        except OverflowError:return [math.inf]
    return [float(p),float(q),float(logp),float(logq)]

def evaluate(exe):
    packet=b''.join(struct.pack('<4iQ3d2Q',op,kind,n,0,seed,a,b,x,draws,work) for op,kind,n,seed,a,b,x,draws,work,status in cases)
    start=time.perf_counter();r=subprocess.run([exe],input=packet,capture_output=True,timeout=35)
    assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr,len(r.stdout))
    at=0;worst={};failures=[]
    for index,c in enumerate(cases):
        op,kind,n,seed,a,b,x,draws,work,expected=c
        status,used_draws,used_work=struct.unpack_from('<iQQ',r.stdout,at);at+=20
        label=(hex(SEED),index,op,kind,a,b,x)
        assert status==expected,(label,'status',status,expected)
        assert used_draws<=draws and used_work<=work,(label,'budget',used_draws,used_work)
        if status:continue
        count=4 if op==2 else 1;got=struct.unpack_from('<'+'d'*count,r.stdout,at);at+=8*count
        want=reference(op,kind,a,b,x)
        for j,(v,w) in enumerate(zip(got,want)):
            assert not math.isnan(w),(label,'invalid oracle reference',j,w)
            if math.isinf(w):
                if v!=w:failures.append((label,j,v,w))
                continue
            if not math.isfinite(v):failures.append((label,j,v,w));continue
            # Relative tail/density error plus a handful of subnormal ULPs;
            # log values use a small absolute error near zero.
            tolerance=max(12*math.ulp(w),2e-11*abs(w)) if op==1 or (op==2 and j<2) else 2e-11*max(1.,abs(w))
            if abs(v-w)>tolerance:failures.append((label,j,v,w,tolerance))
            scale=max(1e-300,abs(w)) if op==1 or (op==2 and j<2) else max(1.,abs(w))
            error=abs(v-w)/scale;worst[(op,kind,j)]=max(worst.get((op,kind,j),0),error)
        if op==2:assert abs(got[0]+got[1]-1)<=2*math.ulp(1.),(label,'complement',got)
    assert at==len(r.stdout),(at,len(r.stdout))
    assert not failures,('distribution differential failures',len(failures),failures[:24])
    print('evaluated',len(cases),'cases,100–450decimal digits, exact binary64 inputs; total',round(time.perf_counter()-start,3),'seconds')
    print('maximum errors: probabilities/densities normalized by max(1e-300,abs(ref)); logs by max(1,abs(ref))',worst)

def large_shape_integral(kind,af,bf,xf,precision=90):
    # Independent defining-integral quadrature, not the production series/CF.
    # Center and scale the integration variable so even a=1e15 has O(1)
    # numerical width. The complete support is retained, with partitions at
    # central and tail coordinates to avoid missing a narrow density peak.
    with mp.workdps(precision):
        a=mp.mpf(af);b=mp.mpf(bf);x=mp.mpf(xf)
        mean=a if kind==2 else a/(a+b)
        sd=mp.sqrt(a) if kind==2 else mp.sqrt(a*b/((a+b)**2*(a+b+1)))
        point=(x-mean)/sd
        norm=mp.loggamma(a) if kind==2 else mp.loggamma(a)+mp.loggamma(b)-mp.loggamma(a+b)
        def density(t):
            y=mean+sd*t
            if not mp.isfinite(y) or y<=0 or (kind==3 and y>=1):return mp.mpf(0)
            lp=(a-1)*mp.log(y)-y-norm if kind==2 else (a-1)*mp.log(y)+(b-1)*mp.log1p(-y)-norm
            return mp.exp(lp)*sd
        lower=x<=mean;lo=-mean/sd;hi=mp.inf if kind==2 else (1-mean)/sd
        partitions=[mp.mpf(v) for v in [-40,-20,-10,-3,0,3,10,20,40]]
        knots=[lo]+[v for v in partitions if lo<v<point]+[point] if lower else [point]+[v for v in partitions if point<v<hi]+[hi]
        probability=mp.quad(density,knots)
        return lower,float(probability),float(mp.log(probability))

def evaluate_large(exe):
    cases=[]
    for kind,a,b in [(2,1e4,1.),(2,1e8,1.),(2,1e12,1.),(3,1e4,2e4),(3,1e8,2e8),(3,1e12,2e12),(3,1e15,1e15)]:
        for z in [-8,-1,0,1,8]:
            mean=a if kind==2 else a/(a+b)
            sd=math.sqrt(a) if kind==2 else math.sqrt(a*b/((a+b)**2*(a+b+1)))
            cases.append((kind,a,b,mean+sd*z,z))
    packet=b''.join(struct.pack('<4iQ3d2Q',2,k,1,0,SEED,a,b,x,0,2000000) for k,a,b,x,z in cases)
    result=subprocess.run([exe],input=packet,capture_output=True,timeout=15)
    assert result.returncode==0 and not result.stderr,(result.returncode,result.stderr)
    at=0;relative=0.;normalized_log=0.;nonconvergent=0
    for kind,a,b,x,z in cases:
        status,draws,work=struct.unpack_from('<iQQ',result.stdout,at);at+=20
        label=(kind,a,b,x,z)
        assert draws==0 and work<=2000000,(label,'budget',draws,work)
        if kind==2 and a==1e12 and z<=0:
            assert status==8 and work==1000001,(label,'nonconvergence',status,work)
            nonconvergent+=1;continue
        assert status==0,(label,'status',status,work)
        got=struct.unpack_from('<4d',result.stdout,at);at+=32
        lower,want,logwant=large_shape_integral(kind,a,b,x)
        assert math.isfinite(want) and want>0 and math.isfinite(logwant),(label,'oracle',want,logwant)
        if (kind==2 and a==1e8 and z==-8) or (kind==3 and a==1e15 and z in [-8,1]):
            _,high,loghigh=large_shape_integral(kind,a,b,x,120)
            assert abs(high-want)<=2*math.ulp(want) and abs(loghigh-logwant)<=2*math.ulp(logwant),(label,'oracle convergence',want,high,logwant,loghigh)
        actual=got[0 if lower else 1];logged=got[2 if lower else 3]
        # A separate measured large-shape envelope, not a relaxation of the
        # ordinary-range 2e-11 gate above and not a global accuracy promise.
        error=abs(actual-want)/want;logerror=abs(logged-logwant)/max(1.,abs(logwant))
        assert error<=2e-8 and logerror<=2e-8,(label,got,want,logwant,error,logerror)
        assert abs(got[0]+got[1]-1)<=2*math.ulp(1.),(label,'complement',got)
        relative=max(relative,error);normalized_log=max(normalized_log,logerror)
        if kind==3 and a==b and x==.5:
            assert got==(.5,.5,-math.log(2),-math.log(2)) and work==1,(label,'exact symmetry',got,work)
    assert at==len(result.stdout),(at,len(result.stdout))
    print('large-shape defining-integral grid',len(cases),'cases,',nonconvergent,'explicit NoConvergence; max relative tail',relative,'normalized log',normalized_log)

if __name__=='__main__':
    evaluate(sys.argv[1]);evaluate_large(sys.argv[1])
