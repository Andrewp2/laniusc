#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, sync::OnceLock, time::Duration};

fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/extended_library/{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let label = name.to_owned();
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{label}: {error}"));
    let exe = common::TempArtifact::new("laniusc_statistics", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn model() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("statistics_model"))
}

#[test]
fn exact_fraction_decimal_oracle_for_streams_merges_pairs_sums_norms_and_all_quantiles() {
    let oracle = r#"
import decimal, fractions, math, random, statistics, struct, subprocess, sys
F=fractions.Fraction
D=decimal.Decimal
decimal.getcontext().prec=110
try:
    import numpy as np
except ImportError:
    np=None
rng=random.Random(0x57a72026)
cases=[]
def dd(x):
    if isinstance(x,F): return D(x.numerator)/D(x.denominator)
    return D.from_float(x)
def close(got,want,label,rel=4e-13,absolute=0):
    want=float(want)
    assert math.isfinite(got) and abs(got-want)<=max(absolute,rel*max(abs(want),1e-300)),(label,got,want)
def add(op,x,y=None,split=0,kind=7,p=.5):
    if y is None: y=[0.]*len(x)
    cases.append((op,x,y,split,kind,p))
def qref(x,p,kind):
    x=sorted(x); n=len(x)
    if p==0 or n==1:return F(x[0])
    if p==1:return F(x[-1])
    # Exact formula at the binary64 h used by the documented no-fuzz API.
    m=[0,0,-.5,0,.5,p,1-p,(p+1)/3,p/4+.375][kind-1]
    h=n*p+m; j=math.floor(h); g=h-j
    if kind==1:g=0 if g==0 else 1
    if kind==2:g=.5 if g==0 else 1
    if kind==3:g=0 if g==0 and j%2==0 else 1
    a=F(x[max(0,min(n-1,j-1))]); b=F(x[max(0,min(n-1,j))])
    return a+(b-a)*F(g)
sets=[[],[7.],[-0.,0.],[1.,3.],[1e12+i*.125 for i in [0,1,7,2,1,5,9]],
      [1e16+i*2 for i in [0,1,4,7,9]],[-1e16+i*2 for i in [0,1,4,7,9]],
      [1e150,-1e150,3e149,-3e149],[1e-150,-1e-150,3e-151,-3e-151],
      [math.ulp(0.),-math.ulp(0.),0.], [float.fromhex('0x1.fffffffffffffp+1023')]*9]
for _ in range(55):
    n=rng.randrange(2,90); base=rng.choice([0,1e12,-1e12,1e16,-1e16]); step=rng.choice([.125,.5,2,17])
    sets.append([base+step*rng.randrange(-30,31) for _ in range(n)])
for x in sets:
    add(0,x)
    for split in sorted(set([0,len(x)//2,len(x)])):
        add(1,x,split=split)
for x in sets[2:-1]:
    if len(x)<2 or max(map(abs,x),default=0)>1e140 or 0<max(map(abs,x),default=0)<1e-140: continue
    y=[-2.5*v+3+(i%3)*.125 for i,v in enumerate(x)]
    add(2,x,y)
    for split in [0,len(x)//2,len(x)]:add(3,x,y,split=split)
for x in [[1e16,1,-1e16],[1e16,1,1,1,-1e16],[],[0.,-0.],[1e-300]*100]+[[rng.uniform(-1e8,1e8) for _ in range(200)] for _ in range(20)]:add(4,x)
for x in [[],[3e200,-4e200],[3e-200,-4e-200],[3*math.ulp(0.),4*math.ulp(0.)],[1e300,1e-300,3e299]]+[[rng.uniform(-1e100,1e100) for _ in range(50)] for _ in range(12)]:add(5,x)
qsets=[[4.],[-0.,0.],[8.,1.,4.,2.,9.,3.],[3.,3.,1.,9.,1.,1.],[-1.7976931348623157e308,1.7976931348623157e308], [math.ulp(0.),3*math.ulp(0.),9*math.ulp(0.)]]
qsets += [[rng.randrange(-20,20)/4 for _ in range(n)] for n in [2,3,4,5,8,17,41]]
for x in qsets:
    for kind in range(1,10):
        for p in [0.,1.,.5,.1,.25,.75,.9,math.nextafter(.5,0),math.nextafter(.5,1)]: add(6,x,kind=kind,p=p)
for op in [0,2,4,5]:
    for v in [float('nan'),float('inf'),-float('inf')]:add(op,[1.,v],[2.,3.])
add(0,[1e308,-1e308]);add(4,[1e308,1e308]);add(5,[1.7e308,1.7e308]);add(6,[]);add(6,[1.,2.],p=-.01);add(6,[1.],kind=0);add(6,[1.,float('nan')])
packet=bytearray()
for op,x,y,split,kind,p in cases:
    packet+=struct.pack('<iiiid',op,len(x),split,kind,p)
    for a,b in zip(x,y): packet+=struct.pack('<dd',a,b)
r=subprocess.run([sys.argv[1]],input=packet,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=20)
assert r.returncode==0,(r.returncode,r.stderr,len(r.stdout))
assert len(r.stdout)==80*len(cases),(len(r.stdout),len(cases))
for idx,(op,x,y,split,kind,p) in enumerate(cases):
    status,mask,n,*v=struct.unpack_from('<iiQ8d',r.stdout,idx*80)
    label=('seed=0x57a72026',idx,op,x,y,split,kind,p)
    if any(not math.isfinite(z) for z in x+y):assert status==3,(label,status);continue
    if (op==0 and x==[1e308,-1e308]) or (op==4 and x==[1e308,1e308]) or (op==5 and x==[1.7e308,1.7e308]):assert status==4,(label,status);continue
    if op==6:
        if not x: assert status==1,(label,status)
        elif not 1<=kind<=9: assert status==8,(label,status)
        elif not 0<=p<=1: assert status==7,(label,status)
        else:
            assert status==0,(label,status)
            close(v[0],qref(x,p,kind),label,rel=8e-15,absolute=2*math.ulp(0.))
            if np is not None and p in [0.,.25,.5,.75,1.] and max(map(abs,x))<1e140 and max(map(abs,x))>1e-250:
                methods=['inverted_cdf','averaged_inverted_cdf','closest_observation','interpolated_inverted_cdf','hazen','weibull','linear','median_unbiased','normal_unbiased']
                close(v[0],float(np.quantile(np.array(x,dtype=np.float64),p,method=methods[kind-1])),('NumPy',label),rel=8e-15,absolute=3e-15)
        continue
    assert status==0 and n==len(x),(label,status,n)
    if op<=1:
        if not x: assert mask==255,(label,mask);continue
        mean=sum(map(F,x))/len(x); m2=sum((F(a)-mean)**2 for a in x); pv=m2/len(x)
        want=[mean,min(x),max(x),m2,pv]
        if len(x)>1: want+=[m2/(len(x)-1)]
        for j,w in enumerate(want):
            # Underflow of representable m2 is documented binary64 behavior.
            close(v[j],w,(label,j),absolute=2*math.ulp(0.))
        close(v[6],dd(pv).sqrt(),(label,6),absolute=4e-162 if float(m2)==0 else 0)
        if len(x)>1:close(v[7],dd(m2/(len(x)-1)).sqrt(),(label,7),absolute=4e-162 if float(m2)==0 else 0)
        assert mask==(160 if len(x)==1 else 0),(label,mask)
    elif op in [2,3]:
        mx=sum(map(F,x))/len(x); my=sum(map(F,y))/len(y)
        xx=sum((F(a)-mx)**2 for a in x); yy=sum((F(b)-my)**2 for b in y); cross=sum((F(a)-mx)*(F(b)-my) for a,b in zip(x,y))
        for j,w in enumerate([mx,my,cross/len(x),cross/(len(x)-1)]):close(v[j],w,(label,j),absolute=3e-15)
        if xx and yy:
            corr=dd(cross)/(dd(xx)*dd(yy)).sqrt(); close(v[4],corr,(label,4),absolute=3e-15)
        else:assert mask&16,(label,mask)
        if xx:
            slope=cross/xx;intercept=my-slope*mx
            close(v[5],slope,(label,5),absolute=3e-15)
            # Intercept subtraction loses precision when an observed center is large.
            close(v[6],intercept,(label,6),absolute=4e-15*max(abs(float(my)),abs(float(slope*mx)),1))
            if yy:close(v[7],corr*corr,(label,7),absolute=3e-15)
            else:assert v[7]==1,(label,v)
        else:assert mask&224==224,(label,mask)
    elif op==4:close(v[0],math.fsum(x),label,rel=3e-15,absolute=2*math.ulp(0.))
    elif op==5:close(v[0],sum((dd(a)**2 for a in x),D(0)).sqrt(),label,rel=3e-15,absolute=math.ulp(0.))
print('verified',len(cases),'independent Fraction/Decimal cases; NumPy quantiles:',np is not None)
"#;
    let result = common::process_output_with_timeout(
        "statistics Fraction and Decimal oracle",
        Command::new("python3")
            .args(["-c", oracle])
            .arg(model().path()),
        Duration::from_secs(35),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
}

#[test]
fn atomic_failures_count_limit_strides_aliases_and_no_allocation() {
    let exe = executable("statistics_contracts");
    let output = common::process_output_with_timeout(
        "statistics atomic and borrowed-storage contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let trace = common::TempArtifact::new("laniusc_statistics", "allocation_trace", None);
    let output = common::process_output_with_timeout(
        "statistics deny every allocation",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let trace = std::fs::read_to_string(trace.path()).unwrap();
    assert!(!trace.contains("mmap("), "statistics allocated: {trace}");
}
