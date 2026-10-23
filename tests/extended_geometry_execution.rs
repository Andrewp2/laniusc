#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};

fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/extended/{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{name}: {e}"));
    let exe = common::TempArtifact::new("laniusc_geometry", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[test]
fn full_range_exact_topology_and_hulls_match_independent_integer_fraction_models() {
    let exe = executable("geometry_model");
    let oracle = r#"
from fractions import Fraction as F
import itertools, random, struct, subprocess, sys
rng=random.Random(0x6e0e2026);lo=-2**31;hi=2**31-1
cases=[]
def cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
def orient(a,b,c):v=cross(a,b,c);return (v>0)-(v<0)
def on(a,b,p):return cross(a,b,p)==0 and all(min(a[i],b[i])<=p[i]<=max(a[i],b[i]) for i in [0,1])
def intersect(a,b,c,d):
    # Parametric rational intersection; separate 1D closed collinear intervals.
    x=(b[0]-a[0],b[1]-a[1]);y=(d[0]-c[0],d[1]-c[1]);q=(c[0]-a[0],c[1]-a[1])
    det=x[0]*y[1]-x[1]*y[0]
    if det:
        t=F(q[0]*y[1]-q[1]*y[0],det);u=F(q[0]*x[1]-q[1]*x[0],det)
        if 0<t<1 and 0<u<1:return 2
        return int(0<=t<=1 and 0<=u<=1)
    if x==(0,0):return int(on(c,d,a))
    if cross(a,b,c):return 0
    k=int(x[0]==0);p=max(min(a[k],b[k]),min(c[k],d[k]));q=min(max(a[k],b[k]),max(c[k],d[k]))
    return 0 if p>q else 1 if p==q else 3
def location(r,p):
    if not r:return 0
    inside=False
    for a,b in zip(r,r[1:]+r[:1]):
        if on(a,b,p):return 1
        if (a[1]>p[1])!=(b[1]>p[1]):
            # Fraction intersection with horizontal ray, no orientation predicate.
            x=F(a[0])+F(p[1]-a[1],b[1]-a[1])*(b[0]-a[0])
            if x>p[0]:inside=not inside
    return 2 if inside else 0
def area(r):return sum(a[0]*b[1]-a[1]*b[0] for a,b in zip(r,r[1:]+r[:1]))
def hull(points):
    # Jarvis gift wrapping, independent from production's sort/stack scans.
    pts=sorted(set(points))
    if len(pts)<2:return pts
    out=[];p=pts[0]
    while True:
        out.append(p);q=next(x for x in pts if x!=p)
        for r in pts:
            turn=cross(p,q,r)
            if turn<0 or (turn==0 and sum((r[i]-p[i])**2 for i in [0,1])>sum((q[i]-p[i])**2 for i in [0,1])):q=r
        p=q
        if p==out[0]:return out
        assert len(out)<=len(pts)
def add(op,p,q=(0,0)):cases.append((op,list(p),q))
anchors=[(lo,lo),(hi,hi-1),(hi-1,hi-2),(lo,hi),(hi,lo),(0,0),(1,1)]
for t in itertools.permutations(anchors,3):add(0,t)
for _ in range(1600):add(0,[(rng.randrange(lo,hi+1),rng.randrange(lo,hi+1)) for _ in range(3)])
segments=[((0,0),(0,0)),((0,0),(4,0)),((4,0),(0,0)),((1,0),(7,0)),((4,0),(8,0)),((5,0),(8,0)),((2,-4),(2,4)),((lo,lo),(hi,hi)),((lo,hi),(hi,lo))]
for a,b in itertools.product(segments,repeat=2):
    for x,y in [(a,b),(a[::-1],b),(b,a)]:add(1,x+y)
for _ in range(800):
    p=[(rng.randrange(lo,hi+1),rng.randrange(lo,hi+1)) for _ in range(4)]
    if rng.randrange(3)==0:p[rng.randrange(4)]=p[0]
    add(1,p)
square=[(lo,lo),(hi,lo),(hi,hi),(lo,hi)]
# This rectangle has area2=+2^63: positive overflow, but its reverse is
# exactly i64::MIN and must succeed. Every ring variant is checked below.
signed_endpoint=[(lo,lo),(0,lo),(0,0),(lo,0)]
rings=[[],[(0,0)],[(0,0),(4,4)],[(0,0),(4,0),(4,4),(0,4)],square, signed_endpoint, square+square[::-1],square*4+square[::-1]*4,[(0,0),(4,4),(0,4),(4,0)],[(hi-8,hi-8),(hi,hi-8),(hi,hi),(hi-8,hi)]]
for _ in range(110):rings.append([(rng.randrange(-30,31),rng.randrange(-30,31)) for _ in range(rng.randrange(1,40))])
for r in rings:
    queries=[(0,0),(2,2),(4,0),(hi,hi),(lo,lo)]
    if r:queries+=r[:4]
    for p in queries:
        for ring in [r,r[::-1],r[1:]+r[:1]]:add(2,ring,p)
sets=[[],[(2,3)]*8,[(i,i) for i in range(-10,11)],square+[(0,0)]*5,anchors]
for _ in range(115):
    domain=rng.choice([4,100,hi]);sets.append([(rng.randrange(-domain,domain+1),rng.randrange(-domain,domain+1)) for _ in range(rng.randrange(1,100))])
for p in sets:
    for variant in [p,p[::-1],p+p]:add(3,variant)
packet=bytearray()
for op,p,q in cases:
    packet+=struct.pack('<10i',op,len(p),*q,0,0,0,0,0,0)
    packet+=b''.join(struct.pack('<ii',*v) for v in p)
r=subprocess.run([sys.argv[1]],input=packet,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=25)
assert r.returncode==0,(r.returncode,r.stderr);offset=0
for index,(op,p,q) in enumerate(cases):
    label=('seed=0x6e0e2026',index,op,p,q)
    status,value,count,flag,x0,y0,x1,y1,al,ah=struct.unpack_from('<10i',r.stdout,offset);offset+=40
    if op==0:assert status==0 and value==orient(*p),label
    if op==1:assert status==0 and value==intersect(*p),label
    if op==2:assert value==location(p,q),(label,value,location(p,q))
    if op in [2,3]:
        expected=hull(p) if op==3 else p
        a=area(expected)
        assert status==(0 if -2**63<=a<2**63 else 5),(label,status,a)
        if status==0:assert struct.unpack('<q',struct.pack('<ii',al,ah))[0]==a,(label,al,ah,a)
        assert flag==int(bool(p)),label
        if p:assert (x0,y0,x1,y1)==(min(x for x,y in p),min(y for x,y in p),max(x for x,y in p),max(y for x,y in p)),label
        if op==3:
            got=[struct.unpack_from('<ii',r.stdout,offset+8*i) for i in range(count)];offset+=8*count
            assert got==expected,(label,got,expected)
            if len(got)>2:assert all(cross(got[i-2],got[i-1],got[i])>0 for i in range(len(got))),label
assert offset==len(r.stdout),(offset,len(r.stdout))
print('integer/Fraction geometry cases:',len(cases))
"#;
    let out = common::process_output_with_timeout(
        "geometry integer/Fraction oracle",
        Command::new("python3").args(["-c", oracle]).arg(exe.path()),
        Duration::from_secs(45),
    );
    assert!(out.status.success(), "{out:?}");
}
#[test]
fn view_limits_finite_vectors_normalization_and_affine_contracts() {
    let exe = executable("geometry_contracts");
    let out = common::process_output_with_timeout(
        "geometry contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(5),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stdout.is_empty() && out.stderr.is_empty());
}
fn no_leaks(text: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in text.lines() {
        if line.starts_with("mmap(") && !line.contains("= -1") {
            let address = line
                .split(" = ")
                .nth(1)
                .unwrap()
                .split_whitespace()
                .next()
                .unwrap();
            assert!(live.insert(address.to_owned()), "{text}");
            count += 1;
        } else if let Some(rest) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(rest.split(',').next().unwrap()),
                "{text}"
            );
        }
    }
    assert!(live.is_empty(), "leaked {live:?}: {text}");
    count
}
#[test]
fn hull_allocation_failure_preserves_input_and_releases_all_temporaries() {
    let exe = executable("geometry_allocation_failure");
    let trace = common::TempArtifact::new("laniusc_geometry", "trace", None);
    let invoke = |failure: Option<usize>| {
        let mut c = Command::new("strace");
        c.args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(i) = failure {
            c.args(["-e", &format!("inject=mmap:error=ENOMEM:when={i}")]);
        }
        c.arg(exe.path());
        let out = common::process_output_with_timeout(
            "hull allocation denial",
            &mut c,
            Duration::from_secs(5),
        );
        assert_eq!(out.status.code(), Some(0), "{out:?}");
        let events = std::fs::read_to_string(trace.path()).unwrap();
        no_leaks(&events);
        events
    };
    let events = invoke(None);
    let count = no_leaks(&events);
    assert!(count >= 3, "{events}");
    for i in 1..=count {
        assert!(invoke(Some(i)).contains("INJECTED"));
    }
}
#[test]
fn finite_vector_and_affine_arithmetic_match_fraction_models() {
    let exe = executable("geometry_float_model");
    let oracle = r#"
from fractions import Fraction as F
import math,random,struct,subprocess,sys
rng=random.Random(0xf1062026);inputs=[];expected=[]
def apply(t,v):return [t[0]*v[0]+t[1]*v[1]+t[4],t[2]*v[0]+t[3]*v[1]+t[5]]
for _ in range(300):
 v=[F(rng.randrange(-100,101),8) for _ in range(24)]
 if v[:2]==[0,0]:v[0]=F(1)
 a,b,c,d=v[:2],v[2:4],v[:3],v[3:6]
 norm2=math.hypot(*a);norm3=math.hypot(*c)
 want=[a[i]+b[i] for i in [0,1]]+[a[i]-b[i] for i in [0,1]]+[a[i]*v[4] for i in [0,1]]+[sum(x*y for x,y in zip(a,b)),a[0]*b[1]-a[1]*b[0],norm2]+[float(x)/norm2 for x in a]
 want += [c[1]*d[2]-c[2]*d[1],c[2]*d[0]-c[0]*d[2],c[0]*d[1]-c[1]*d[0],sum(x*y for x,y in zip(c,d)),norm3]+[float(x)/norm3 for x in c]
 mapped=apply(v[6:12],apply(v[12:18],a));want+=mapped+mapped+[0]
 want += [c[i]+d[i] for i in range(3)]+[c[i]-d[i] for i in range(3)]+[c[i]*v[4] for i in range(3)]
 inputs.append(v);expected.append(want)
packet=b''.join(struct.pack('<24d',*map(float,v)) for v in inputs)
r=subprocess.run([sys.argv[1]],input=packet,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
assert r.returncode==0 and not r.stderr,(r.returncode,r.stderr)
assert len(r.stdout)==264*len(inputs),len(r.stdout)
for i,want in enumerate(expected):
 got=struct.unpack_from('<33d',r.stdout,i*264)
 for j,(a,b) in enumerate(zip(got,want)):
  b=float(b);assert math.isfinite(a) and abs(a-b)<=8e-14*max(1,abs(b)),('seed=0xf1062026',i,j,inputs[i],a,b)
print('Fraction vector/affine cases:',len(inputs))
"#;
    let out = common::process_output_with_timeout(
        "geometry Fraction vector/affine oracle",
        Command::new("python3").args(["-c", oracle]).arg(exe.path()),
        Duration::from_secs(25),
    );
    assert!(out.status.success(), "{out:?}");
}
