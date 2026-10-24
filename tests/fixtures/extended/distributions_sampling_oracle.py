"""Published xoshiro stream consumption + independent distribution diagnostics."""
import math, random, struct, subprocess, sys
import mpmath as mp
mp.mp.dps=70
MASK=(1<<64)-1
class Source:
    def __init__(self,seed):
        self.s=[];self.draws=0;self.work=0
        for _ in range(4):
            seed=(seed+0x9e3779b97f4a7c15)&MASK;z=seed
            z=((z^(z>>30))*0xbf58476d1ce4e5b9)&MASK;z=((z^(z>>27))*0x94d049bb133111eb)&MASK
            self.s.append(z^(z>>31))
    def raw(self):
        a,b,c,d=self.s;v=(a+d)&MASK;v=((v<<23)|(v>>41))&MASK;result=(v+a)&MASK
        t=(b<<17)&MASK;c^=a;d^=b;b^=c;a^=d;c^=t;d=((d<<45)|(d>>19))&MASK
        self.s=[a,b,c,d];self.draws+=1;return result
    def unit(self,open=False):
        while True:
            self.work+=1;value=(self.raw()>>11)*2**-53
            if value or not open:return value
    def normal(self):return math.sqrt(-2*math.log(self.unit(True)))*math.cos(math.tau*self.unit())
    def gamma(self,a):
        raised=a+1 if a<1 else a;d=raised-1/3;c=(1/math.sqrt(d))/3
        while True:
            self.work+=1;x=self.normal();linear=1+c*x
            if linear<=0:continue
            v=linear**3;u=self.unit(True);square=x*x
            if u<1-.0331*square*square or math.log(u)<.5*square+d*(1-v+math.log(v)):
                return d*v,math.log(d)+3*math.log1p(c*x),math.log(self.unit(True)) if a<1 else 0.
    def sample(self,kind,a,b):
        if kind==0:return a+b*self.normal()
        if kind==1:return -math.log1p(-self.unit())/a
        if kind==2:
            v,lv,boost=self.gamma(a)
            if a<1:return math.exp(lv+math.log(b)+boost/a)
            return math.exp(lv+math.log(b)) if b<1 else v*b
        av,al,au=self.gamma(a);bv,bl,bu=self.gamma(b);small=min(1.,a,b)
        delta=(al-bl)+((small/a)*au-(small/b)*bu)/small
        if delta>=0:return 1/(1+math.exp(-delta))
        e=math.exp(delta);return e/(1+e)

cases=[(0,0.,1.),(0,-10.,.1),(0,1e10,1e3),(0,0.,1e-100),
       (1,.01,0.),(1,1.,0.),(1,1e100,0.),
       *[(2,a,b) for a,b in [(.01,1.),(.1,2.),(.5,.125),(1.,1.),(2.,3.),(10.,1.),(1000.,.01),(1e8,1.)]],
       *[(3,a,b) for a,b in [(.001,.003),(.01,.01),(.1,3.),(3.,.1),(.5,.5),(1.,1.),(2.,3.),(10.,20.),(1000.,1000.)]]]
requests=[(kind,a,b,8000,0x53414d504c4500+i) for i,(kind,a,b) in enumerate(cases)]
requests.append((1,1.,0.,200000,0x5343414c45))
packet=b''.join(struct.pack('<4iQ3d2Q',3,k,n,0,seed,a,b,0.,10000000,10000000) for k,a,b,n,seed in requests)
r=subprocess.run([sys.argv[1]],input=packet,capture_output=True,timeout=35)
assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr,len(r.stdout))
at=0;total=0
for case,(kind,a,b,n,seed) in enumerate(requests):
    source=Source(seed);values=[];last_draws=last_work=0
    for i in range(n):
        status,draws,work,value=struct.unpack_from('<iQQd',r.stdout,at);at+=28
        assert status==0 and math.isfinite(value),(case,i,status,value)
        assert draws>=last_draws and work>=last_work and draws<=10000000 and work<=10000000
        last_draws,last_work=draws,work
        if i<512:
            want=source.sample(kind,a,b)
            assert abs(value-want)<=2e-12*max(1e-300,abs(want)),('stream',case,i,hex(seed),value,want)
            assert (draws,work)==(source.draws,source.work),('consumption',case,i,draws,work,source.draws,source.work)
        if kind in [1,2]:assert value>=0
        if kind==3:assert 0<=value<=1
        values.append(value)
    if kind==0:mean=a;variance=b*b;kurtosis=3.;points=[a-b,a,a+b];cdf=lambda x:float(mp.erfc(-(mp.mpf(x)-a)/b/mp.sqrt(2))/2)
    elif kind==1:mean=1/a;variance=1/(a*a);kurtosis=9.;points=[.1/a,1/a,3/a];cdf=lambda x:-math.expm1(-a*x)
    elif kind==2:
        mean=a*b;variance=a*b*b;kurtosis=3+6/a;points=[max(.01*b,(a-math.sqrt(a))*b),a*b,(a+math.sqrt(a))*b]
        # At shape1e8 the normal limit error is <1e-4, far below the empirical
        # acceptance band; moderate shapes use the independent gamma integral.
        cdf=(lambda x:float(mp.gammainc(a,0,mp.mpf(x)/b,regularized=True))) if a<1e6 else (lambda x:.5*math.erfc(-(x/b-a)/math.sqrt(2*a)))
    else:
        s=a+b;mean=a/s;variance=a*b/(s*s*(s+1));kurtosis=3+6*((a-b)**2*(s+1)-a*b*(s+2))/(a*b*(s+2)*(s+3))
        points=[max(1e-6,mean-math.sqrt(variance)),mean,min(1-1e-6,mean+math.sqrt(variance))]
        cdf=lambda x:float(mp.betainc(a,b,0,x,regularized=True))
    actual=math.fsum(values)/n;sample_variance=math.fsum((x-actual)**2 for x in values)/n
    assert abs(actual-mean)<=9*math.sqrt(variance/n)+8*math.ulp(mean),('mean',case,hex(seed),actual,mean)
    variance_bound=10*variance*(math.sqrt(max(.01,kurtosis-1)/n)+1/n)+20*math.ulp(variance)
    assert abs(sample_variance-variance)<=variance_bound,('variance',case,hex(seed),sample_variance,variance,variance_bound)
    for point in points:
        p=cdf(point);observed=sum(x<=point for x in values)
        tolerance=9*math.sqrt(n*p*(1-p))+8+(n*1e-4 if kind==2 and a>=1e6 else 0)
        assert abs(observed-n*p)<=tolerance,('cdf count',case,hex(seed),point,observed,n*p,tolerance)
    total+=n
assert at==len(r.stdout),(at,len(r.stdout))
print('verified',total,'samples across',len(requests),'seeded streams; first512perstream consumption/reproducibility, support, moments and independentCDF counts')
