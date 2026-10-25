"""Independent discrete-law diagnostics, dyadic streams and scripted decisions."""
import math,struct,subprocess,sys,time
import mpmath as mp
mp.mp.dps=110
MASK=2**64-1
class Source:
    def __init__(self,seed):
        self.s=[];self.draws=0;self.minimum_work=0
        for _ in range(4):
            seed=(seed+0x9e3779b97f4a7c15)&MASK;z=seed
            z=((z^(z>>30))*0xbf58476d1ce4e5b9)&MASK;z=((z^(z>>27))*0x94d049bb133111eb)&MASK
            self.s.append(z^(z>>31))
    def raw(self):
        a,b,c,d=self.s;v=(a+d)&MASK;v=((v<<23)|(v>>41))&MASK;result=(v+a)&MASK
        t=(b<<17)&MASK;c^=a;d^=b;b^=c;a^=d;c^=t;d=((d<<45)|(d>>19))&MASK
        self.s=[a,b,c,d];self.draws+=1;self.minimum_work+=1;return result
    def unit(self,open=False):
        while True:
            value=(self.raw()>>11)*2**-53
            if value or not open:return value
    def trial(self,p):
        if p in [0.,1.]:return int(p)
        numerator,denominator=p.as_integer_ratio();bits=denominator.bit_length()-1
        while True:
            count=min(bits,64)
            prefix=(numerator>>(bits-count))<<(64-count)
            word=self.raw()
            if word<prefix:return 1
            if word>prefix or bits<=64:return 0
            bits-=64;numerator&=(1<<bits)-1
    def conditional(self,kind,n,p,u):
        # High precision inversion of the defining PMFs; it does not copy
        # native lower recurrence rounding or upper binary-search/CDF work.
        with mp.workdps(110):
            probability=mp.mpf(p)
            if kind==1:
                nonzero=-mp.expm1(n*mp.log1p(-probability))
                mass=n*probability*mp.exp((n-1)*mp.log1p(-probability))/nonzero
            else:mass=probability/mp.expm1(probability)
            accumulated=mass;k=1;uniform=mp.mpf(u)
            while uniform>accumulated:
                k+=1
                mass*=((n-k+1)*probability/(k*(1-probability))) if kind==1 else probability/k
                accumulated+=mass
                assert k<1000
            return k
    def log_pmf(self,kind,n,p,k):
        p=mp.mpf(p)
        if kind==1:return mp.loggamma(n+1)-mp.loggamma(k+1)-mp.loggamma(n-k+1)+k*mp.log(p)+(n-k)*mp.log1p(-p)
        return -p+k*mp.log(p)-mp.loggamma(k+1)
    def reject(self,kind,n,p):
        if kind==1:
            spread=math.sqrt(n*p*(1-p));b=1.15+2.53*spread;a=-.0873+.0248*b+.01*p;c=n*p+.5;vr=.92-4.2/b
            scale=(2.83+5.1/b)*spread;mode=math.floor((n+1)*p);modal=self.log_pmf(1,n,p,mode)
        else:
            b=.931+2.53*math.sqrt(p);a=-.059+.02483*b;c=p+.43;vr=.9277-3.6224/(b-2)
            scale=1.1239+1.1328/(b-3.4)
        while True:
            self.minimum_work+=1;u=self.unit()-.5;v=self.unit();us=.5-abs(u)
            if us==0:continue
            k=math.floor((2*a/us+b)*u+c)
            if k<0 or (kind==1 and k>n) or (kind==3 and us<.013 and v>us):continue
            if us>=.07 and v<=vr:return k
            left=mp.log(v)+mp.log(scale if kind==3 else 1/scale)-mp.log(a/(us*us)+b)
            if kind==1:left=mp.log(v)+mp.log(scale)-mp.log(a/(us*us)+b)
            right=self.log_pmf(kind,n,p,k)-(modal if kind==1 else 0)
            if left<=right:return k
    def sample(self,kind,n,p):
        if kind==0:return self.trial(p)
        if kind==1:
            if n==0 or p==0:return 0
            if p==1:return n
            if n==1:return self.trial(p)
            reflect=p>.5;r=1-p if reflect else p
            if n*r<10:
                if not self.trial(-math.expm1(n*math.log1p(-r))):value=0
                else:value=self.conditional(1,n,r,self.unit())
            else:value=self.reject(1,n,r)
            return n-value if reflect else value
        if kind==2:
            if p==1:return 0
            return math.floor(math.log(self.unit(True))/math.log1p(-p))
        if p==0:return 0
        if p<10:
            if not self.trial(-math.expm1(-p)):return 0
            return self.conditional(3,0,p,self.unit())
        return self.reject(3,0,p)

def packet(op,kind,n,p,count,seed,draws=10000000,work=100000000):
    return struct.pack('<3iIQdqQQ',op,kind,count,n,seed,p,0,draws,work)
def scripted(exe,kind,n,p,words,expected,draws,work=None,status=0,fail_at=0,quota=100000):
    assert len(words)<=32
    message=packet(4,kind,n,p,1,fail_at,draws=10000000,work=quota)+struct.pack('<32Q',*(words+[0]*(32-len(words))))
    result=subprocess.run([exe],input=message,capture_output=True,timeout=5)
    assert result.returncode==0 and not result.stderr,(result.returncode,result.stderr)
    code,used,charged=struct.unpack_from('<iQQ',result.stdout)
    label=(kind,n,p,words[:3],status,expected)
    assert (code,used)==(status,draws),(label,code,used,charged)
    if work is not None:assert charged==work,(label,charged,work)
    if status:assert len(result.stdout)==20
    else:assert len(result.stdout)==28 and struct.unpack_from('<q',result.stdout,20)[0]==expected,(label,result.stdout)
    return charged

def scripted_models(exe):
    # Independent rational-prefix cases, including the117-bit chunk boundary.
    scripted(exe,0,1,math.ulp(0.),[0]*17,1,17,17)
    scripted(exe,0,1,math.ulp(0.),[1],0,1,1)
    scripted(exe,0,1,2**-64,[0],1,1,1)
    scripted(exe,0,1,2**-64,[1,0],0,2,2)
    scripted(exe,0,1,2**-65,[0,2**63-1],1,2,2)
    scripted(exe,0,1,2**-65,[0,2**63],0,2,2)
    scripted(exe,0,1,.5,[2**63-1],1,1,1)
    scripted(exe,0,1,.5,[2**63],0,1,1)
    near_one=math.nextafter(1.,0.);prefix=2**64-2048
    scripted(exe,0,1,near_one,[prefix-1],1,1,1)
    scripted(exe,0,1,near_one,[prefix],0,1,1)
    for p in [0.,1.]:scripted(exe,0,1,p,[],int(p),0,0,fail_at=1,quota=0)
    # Lost-information regressions: normalized first mass and upper-grid
    # quantiles are defined by110-digit PMFs, not native association.
    scripted(exe,1,2,2**-53,[0,0],1,2,2)
    for n,p,want in [(20,.49,20),(100,.0999,41),(2**32-1,9.99/(2**32-1),45)]:
        source=Source(0);exact=source.conditional(1,n,p,1-2**-53);assert exact==want
        scripted(exe,1,n,p,[0,MASK],exact,2)
    scripted(exe,3,0,math.ulp(0.),[0]*18,1,18,18)
    scripted(exe,0,1,math.ulp(0.),[0]*17,None,16,16,status=8,fail_at=16)
    scripted(exe,2,0,math.ulp(0.),[2**63],None,1,1,status=2)

    # First proposed point is outside the squeeze. Exact-input MP PMFs
    # determine the acceptance boundary; neighboring choices force both
    # branches, followed by a known squeezed fallback on rejection.
    decisions=0;left53=8646911284551352;left=left53*2**-53;u=left-.5;us=.5-abs(u)
    for kind,n,p in [(1,100,.2),(1,1000000,.1),(1,2**32-1,.1),(1,2**32-1,.5),(3,0,10.),(3,0,100.),(3,0,1e9)]:
        model=Source(0)
        if kind==1:
            spread=math.sqrt(n*p*(1-p));b=1.15+2.53*spread;a=-.0873+.0248*b+.01*p;c=n*p+.5;scale=(2.83+5.1/b)*spread
            k=math.floor((2*a/us+b)*u+c);mode=math.floor((n+1)*p)
            threshold=mp.exp(model.log_pmf(1,n,p,k)-model.log_pmf(1,n,p,mode))*mp.mpf(a/(us*us)+b)/scale
        else:
            b=.931+2.53*math.sqrt(p);a=-.059+.02483*b;c=p+.43;scale=1.1239+1.1328/(b-3.4)
            k=math.floor((2*a/us+b)*u+c)
            threshold=mp.exp(model.log_pmf(3,0,p,k))*mp.mpf(a/(us*us)+b)/scale
        assert 0<threshold<1 and .013<us<.07,(kind,n,p,k,threshold)
        fallback=math.floor(c)
        for factor,expected,count in [(mp.mpf('.99999'),k,2),(mp.mpf('1.00001'),fallback,4)]:
            v53=int(mp.floor(threshold*factor*2**53))
            scripted(exe,kind,n,p,[left53<<11,v53<<11,2**63,0],expected,count,3 if count==2 else 6)
            decisions+=1
    print('scripted dyadic, rare conditional-quantile and',decisions,'independent MP rejection-boundary decisions passed')

def monte_carlo(exe):
    laws=[(0,1,p) for p in [0.,.01,.5,.9,1.]]
    laws += [(1,n,p) for n,p in [(0,.5),(1,.3),(20,.49),(100,.001),(100,.0999),(100,.7),(1000000,.1),(2**32-1,9.99/(2**32-1)),(2**32-1,.5)]]
    laws += [(2,0,p) for p in [.001,.1,.5,1.]]
    laws += [(3,0,p) for p in [0.,.01,1.,9.999,10.,100.,1e6,1e9]]
    requests=[(kind,n,p,4000,0x444953430000+i) for i,(kind,n,p) in enumerate(laws)]
    requests.append((3,0,100.,200000,0x5343414c45))
    result=subprocess.run([exe],input=b''.join(packet(3,k,n,p,count,seed) for k,n,p,count,seed in requests),capture_output=True,timeout=25)
    assert result.returncode==0 and not result.stderr,(result.returncode,result.stderr)
    at=0;total=0
    for case,(kind,n,p,count,seed) in enumerate(requests):
        values=[];source=Source(seed);last_work=last_draws=0
        for i in range(count):
            status,draws,work,value=struct.unpack_from('<iQQq',result.stdout,at);at+=28
            assert status==0 and value>=0,(case,i,status,value,draws,work)
            assert draws>=last_draws and work>=last_work and draws<=10000000 and work<=100000000
            last_draws,last_work=draws,work
            if kind==0:assert value<=1
            if kind==1:assert value<=n
            if i<128:
                want=source.sample(kind,n,p);assert value==want,('stream',case,i,hex(seed),value,want)
                assert draws==source.draws and work>=source.minimum_work,('consumption',case,i,draws,work,source.draws,source.minimum_work)
            values.append(value)
        if kind==0:mean=p;variance=p*(1-p);kurtosis=(1/variance-3) if variance else 0
        elif kind==1:mean=n*p;variance=n*p*(1-p);kurtosis=3+(1-6*p*(1-p))/variance if variance else 0
        elif kind==2:mean=(1-p)/p;variance=(1-p)/(p*p);kurtosis=9+p*p/(1-p) if p<1 else 0
        else:mean=p;variance=p;kurtosis=3+1/p if p else 0
        actual=math.fsum(values)/count;observed=math.fsum((x-actual)**2 for x in values)/count
        if not variance:assert all(x==mean for x in values);continue
        assert abs(actual-mean)<=9*math.sqrt(variance/count)+8*math.ulp(mean),('mean',case,hex(seed),actual,mean)
        bound=10*variance*(math.sqrt(max(.01,kurtosis-1)/count)+1/count)+20*math.ulp(variance)
        assert abs(observed-variance)<=bound,('variance',case,observed,variance,bound)
        for point in sorted(set([max(-1,math.floor(mean-math.sqrt(variance))),math.floor(mean),math.floor(mean+math.sqrt(variance))])):
            allowance=0.
            if point<0:probability=0.
            elif kind==0:probability=1-p if point==0 else 1.
            elif kind==2:probability=-math.expm1((point+1)*math.log1p(-p))
            elif kind==1 and n>=1000000 and min(n*p,n*(1-p))>1000:
                probability=.5*math.erfc(-(point+.5-mean)/math.sqrt(2*variance))
                allowance=.56*(p*p+(1-p)**2)/math.sqrt(variance) # Berry–Esseen bound, test only.
            elif kind==1:probability=float(mp.betainc(n-point,point+1,0,1-mp.mpf(p),regularized=True)) if point<n else 1.
            elif p>=1e6:
                probability=.5*math.erfc(-(point+.5-mean)/math.sqrt(2*variance));allowance=1/math.sqrt(p)
            else:probability=float(mp.gammainc(point+1,p,mp.inf,regularized=True))
            expected=count*probability;seen=sum(x<=point for x in values)
            assert abs(seen-expected)<=9*math.sqrt(count*probability*(1-probability))+8+count*allowance,('CDF count',case,point,seen,expected,allowance)
        total+=count
    assert at==len(result.stdout),(at,len(result.stdout))
    print('verified',sum(x[3] for x in requests),'samples over',len(requests),'streams,128 exact stream/draw checks each; support, independent moments and CDF counts')

if __name__=='__main__':
    started=time.monotonic();scripted_models(sys.argv[1]);monte_carlo(sys.argv[1]);print('sampling model time',round(time.monotonic()-started,3))
