"""Exact-input high precision PMFs, independent finite sums and quadrature."""
import functools,math,random,struct,subprocess,sys,time
import mpmath as mp
mp.mp.dps=110
MAX_COUNT=2**53-1
SEED=0x4449534352455445
cases=[]
def add(op,kind,n,p,k,status=0,work=2000000):
    cases.append((op,kind,n,float(p),int(k),status,work))
def all_ops(kind,n,p,k):
    for op in range(3):
        status=2 if kind>=2 and k>MAX_COUNT else 4 if kind==3 and p>0 and k==MAX_COUNT and op==2 else 0
        add(op,kind,n,p,k,status)
probabilities=[0.,math.ulp(0.),1e-300,1e-20,2**-53,.01,.25,.5,.9,math.nextafter(1.,0.),1.]
for p in probabilities:
    for k in [-1,0,1,2,MAX_COUNT,2**63-1]:all_ops(0,1,p,k)
for n in [0,1,2,7,32,100,1000]:
    for p in probabilities:
        for k in sorted(set([-1,0,1,2,n//2,n-1,n,n+1])):all_ops(1,n,p,k)
for p in probabilities[1:]:
    for k in [-1,0,1,2,10,1000,MAX_COUNT,MAX_COUNT+1]:all_ops(2,0,p,k)
for mean in [0.,math.ulp(0.),1e-300,1e-10,.1,1.,9.999999999,10.,100.,1000.]:
    for k in [-1,0,1,2,10,100,1000,MAX_COUNT,MAX_COUNT+1]:all_ops(3,0,mean,k)
rng=random.Random(SEED)
for _ in range(120):
    n=rng.randrange(2,1001);p=rng.random();k=rng.randrange(n+1)
    all_ops(1,n,p,k)
for kind,p in [(0,-.1),(1,math.nan),(2,0.),(3,1e9+1),(3,math.inf)]:
    for op in range(3):add(op,kind,100,p,1,1)
for kind in range(4):add(2,kind,100,.5,0,6,work=0)

large=[]
for n in [10000,1000000,2**32-1]:
    for p in [1e-9,.1,.5,1-1e-9]:
        mean=n*p;sd=math.sqrt(n*p*(1-p))
        for z in [-8,-1,0,1,8]:
            k=math.floor(mean+z*sd)
            if 0<=k<n:
                for op in range(3):large.append((op,1,n,p,k,0,2000000))
for mean in [1e4,1e6,1e9]:
    for z in [-8,-1,0,1,8]:
        k=math.floor(mean+z*math.sqrt(mean))
        for op in range(3):large.append((op,3,0,mean,k,0,2000000))

def complements(logsmall,lower):
    logother=mp.log(-mp.expm1(logsmall))
    return (logsmall,logother) if lower else (logother,logsmall)
def binomial_log(n,p,k):
    if k<0 or k>n:return mp.ninf
    if p==0:return mp.mpf(0) if k==0 else mp.ninf
    if p==1:return mp.mpf(0) if k==n else mp.ninf
    return mp.loggamma(n+1)-mp.loggamma(k+1)-mp.loggamma(n-k+1)+k*mp.log(p)+(n-k)*mp.log1p(-p)
def binomial_series(n,p,k):
    if p>.5:
        a,b=binomial_series(n,1-p,n-k-1);return b,a
    lower=k<n*p;start=k if lower else k+1
    logged=binomial_log(n,p,start);term=mp.mpf(1);total=term;j=start
    for _ in range(20000):
        if lower:
            if j==0:break
            term*=j*(1-p)/((n-j+1)*p);j-=1
        else:
            if j==n:break
            term*=(n-j)*p/((j+1)*(1-p));j+=1
        total+=term
        if abs(term)<=abs(total)*mp.eps:break
    else:raise AssertionError(('reference binomial series did not converge',n,p,k))
    return complements(logged+mp.log(total),lower)
def poisson_log(mean,k):
    if k<0:return mp.ninf
    if mean==0:return mp.mpf(0) if k==0 else mp.ninf
    return -mean+k*mp.log(mean)-mp.loggamma(k+1)
def poisson_series(mean,k):
    lower=k<mean;start=k if lower else k+1
    logged=poisson_log(mean,start);term=mp.mpf(1);total=term;j=start
    for _ in range(20000):
        if lower:
            if j==0:break
            term*=j/mean;j-=1
        else:term*=mean/(j+1);j+=1
        total+=term
        if abs(term)<=abs(total)*mp.eps:break
    else:raise AssertionError(('reference Poisson series did not converge',mean,k))
    return complements(logged+mp.log(total),lower)

def quadrature(kind,a,b,x,precision=110):
    # Defining density integral with complete support, centered coordinates,
    # and partitions resolving the narrow central mass at the largest n/lambda.
    with mp.workdps(precision):
        a=mp.mpf(a);b=mp.mpf(b);x=mp.mpf(x)
        mean=a if kind==3 else a/(a+b)
        sd=mp.sqrt(a) if kind==3 else mp.sqrt(a*b/((a+b)**2*(a+b+1)))
        at=(x-mean)/sd;lo=-mean/sd;hi=mp.inf if kind==3 else (1-mean)/sd
        norm=mp.loggamma(a) if kind==3 else mp.loggamma(a)+mp.loggamma(b)-mp.loggamma(a+b)
        def density(t):
            y=mean+sd*t
            if not mp.isfinite(y) or y<=0 or (kind==1 and y>=1):return mp.mpf(0)
            logged=(a-1)*mp.log(y)-y-norm if kind==3 else (a-1)*mp.log(y)+(b-1)*mp.log1p(-y)-norm
            return mp.exp(logged)*sd
        lower=x<=mean
        stops=[mp.mpf(i) for i in [-40,-20,-10,-3,0,3,10,20,40]]
        knots=[lo]+[t for t in stops if lo<t<at]+[at] if lower else [at]+[t for t in stops if at<t<hi]+[hi]
        small=mp.quad(density,knots)
        # Both identities swap the continuous lower and upper probabilities.
        return complements(mp.log(small),not lower)

@functools.lru_cache(maxsize=None)
def reference(kind,n,pf,k):
    # 450digits retain 1-p even for the smallest binary64 subnormal. Log
    # complements are computed directly, never from a rounded ordinary tail.
    with mp.workdps(450 if 0<pf<1e-70 else 110):
        p=mp.mpf(pf)
        if k<0:return mp.ninf,mp.ninf,mp.mpf(0)
        if kind<=1:
            n=1 if kind==0 else n;lp=binomial_log(n,p,k)
            if k>=n or p==0:return lp,mp.mpf(0),mp.ninf
            if p==1:return lp,mp.ninf,mp.mpf(0)
            if k==0:logs=complements(n*mp.log1p(-p),True)
            elif k==n-1:logs=complements(n*mp.log(p),False)
            elif n>10000 and min(n*p,n*(1-p))>1000:logs=quadrature(1,k+1,n-k,p)
            else:logs=binomial_series(n,p,k)
            return lp,*logs
        if kind==2:
            if p==1:return (mp.mpf(0) if k==0 else mp.ninf),mp.mpf(0),mp.ninf
            return mp.log(p)+k*mp.log1p(-p),*complements((k+1)*mp.log1p(-p),False)
        lp=poisson_log(p,k)
        if p==0:return lp,mp.mpf(0),mp.ninf
        if k==0:logs=complements(-p,True)
        elif p>10000:logs=quadrature(3,k+1,1,p)
        else:logs=poisson_series(p,k)
        return lp,*logs

def evaluate(exe,requests,relative_gate,label):
    packet=b''.join(struct.pack('<3iIQdqQQ',op,kind,1,n,SEED,p,k,0,work) for op,kind,n,p,k,status,work in requests)
    result=subprocess.run([exe],input=packet,capture_output=True,timeout=15)
    assert result.returncode==0 and not result.stderr,(result.returncode,result.stderr)
    at=0;worst_probability=0.;worst_log=0.
    for index,(op,kind,n,p,k,expected,work) in enumerate(requests):
        status,draws,used=struct.unpack_from('<iQQ',result.stdout,at);at+=20
        context=(label,index,op,kind,n,p,k)
        assert status==expected,(context,'status',status,expected)
        assert draws==0 and used<=work,(context,'budget',draws,used,work)
        if status:continue
        size=4 if op==2 else 1;got=struct.unpack_from('<'+'d'*size,result.stdout,at);at+=8*size
        lp,logp,logq=reference(kind,n,p,k)
        want=[float(lp)] if op==0 else [float(mp.exp(lp))] if op==1 else [float(mp.exp(logp)),float(mp.exp(logq)),float(logp),float(logq)]
        for j,(v,w) in enumerate(zip(got,want)):
            assert not math.isnan(w),(context,'NaN reference',j)
            if math.isinf(w):assert v==w,(context,j,v,w);continue
            assert math.isfinite(v),(context,j,v,w)
            ordinary=op==1 or (op==2 and j<2)
            tolerance=max(12*math.ulp(w),relative_gate*abs(w)) if ordinary else relative_gate*max(1.,abs(w))
            assert abs(v-w)<=tolerance,(context,j,v,w,tolerance)
            error=abs(v-w)/(max(1e-300,abs(w)) if ordinary else max(1.,abs(w)))
            if ordinary:worst_probability=max(worst_probability,error)
            else:worst_log=max(worst_log,error)
        if op==2:
            assert 0<=got[0]<=1 and 0<=got[1]<=1 and abs(got[0]+got[1]-1)<=2*math.ulp(1.),(context,got)
    assert at==len(result.stdout),(at,len(result.stdout))
    print(label,len(requests),'cases; probability error/max(1e-300,abs(ref))',worst_probability,'normalized log error',worst_log)

if __name__=='__main__':
    start=time.monotonic();evaluate(sys.argv[1],cases,2e-11,'ordinary/edge');evaluate(sys.argv[1],large,1e-8,'large-count')
    print('model seed',hex(SEED),'time',round(time.monotonic()-start,3))
