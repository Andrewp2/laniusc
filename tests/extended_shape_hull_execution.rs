#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
    sync::OnceLock,
    time::Duration,
};
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/shape_hull.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("shape_hull", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap();
        let exe = common::TempArtifact::new("laniusc_shape_hull", "consumer", None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}
fn file(input: &[u8]) -> common::TempArtifact {
    let f = common::TempArtifact::new("laniusc_shape_hull", "input", None);
    f.write_bytes(input);
    f
}
fn invoke(args: &[&str], input: &[u8]) -> Output {
    let f = file(input);
    let mut c = Command::new(executable().path());
    c.args(args)
        .stdin(Stdio::from(std::fs::File::open(f.path()).unwrap()));
    common::process_output_with_timeout("shape-hull consumer", &mut c, Duration::from_secs(10))
}
fn fail(out: &Output, status: i32, diagnostic: &str) {
    assert_eq!(out.status.code(), Some(status), "{out:?}");
    assert!(out.stdout.is_empty(), "{out:?}");
    assert!(
        String::from_utf8_lossy(&out.stderr).contains(diagnostic),
        "{out:?}"
    );
}
#[test]
fn csv_consumer_matches_integer_hull_area_bounds_and_is_deterministic_at_scale() {
    let oracle = r#"
import csv,io,random,subprocess,sys
rng=random.Random(0x5a9e2026)
def cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
def hull(p):
 p=sorted(set(p))
 if len(p)<2:return p
 out=[];x=p[0]
 while True:
  out.append(x);q=next(v for v in p if v!=x)
  for v in p:
   turn=cross(x,q,v)
   if turn<0 or (turn==0 and sum((v[i]-x[i])**2 for i in [0,1])>sum((q[i]-x[i])**2 for i in [0,1])):q=v
  x=q
  if x==out[0]:return out
sets=[[],[(3,5)]*12,[(i,-2*i+7) for i in range(-20,21)],[(0,0),(7,0),(7,7),(0,7),(2,2)]]
sets += [[(rng.randrange(-1000000,1000001),rng.randrange(-1000000,1000001)) for _ in range(n)] for n in [2,3,7,25,101,2000]]
sets += [[(-2**31,-2**31),(-2**31+1,-2**31),(-2**31+1,-2**31+1),(-2**31,-2**31+1)]]
# 12,000 records exercise streaming and n log n sorting; the oracle wraps four edges.
sets += [[(rng.randrange(-20000,20001),rng.randrange(-20000,20001)) for _ in range(12000)]+[(-20001,-20001),(20001,-20001),(20001,20001),(-20001,20001)]]
for i,p in enumerate(sets):
 expected=hull(p);outputs=[]
 for shuffled in [p,list(reversed(p))]:
  data=io.StringIO();w=csv.writer(data,lineterminator='\r\n',quoting=csv.QUOTE_ALL);w.writerows(shuffled)
  r=subprocess.run([sys.argv[1]],input=data.getvalue().encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
  assert r.returncode==0 and not r.stderr,(i,r.returncode,r.stderr)
  outputs.append(r.stdout);rows=list(csv.DictReader(io.StringIO(r.stdout.decode())))
  got=[(int(row['x']),int(row['y'])) for row in rows if row['kind']=='vertex'];assert got==expected,(i,got,expected)
  a=sum(x[0]*y[1]-x[1]*y[0] for x,y in zip(expected,expected[1:]+expected[:1]));assert [int(row['value']) for row in rows if row['kind']=='area2']==[a],i
  bounds=[(row['kind'],int(row['x']),int(row['y'])) for row in rows if row['kind'] in ['minimum','maximum']]
  assert bounds==([] if not p else [('minimum',min(x for x,y in p),min(y for x,y in p)),('maximum',max(x for x,y in p),max(y for x,y in p))]),i
 assert outputs[0]==outputs[1],i
print('shape-hull CSV cases',len(sets))
"#;
    let out = common::process_output_with_timeout(
        "shape-hull CSV integer oracle",
        Command::new("python3")
            .args(["-c", oracle])
            .arg(executable().path()),
        Duration::from_secs(45),
    );
    assert!(out.status.success(), "{out:?}");
}
#[test]
fn malformed_coordinates_csv_arguments_and_limits_have_staged_errors_before_stdout() {
    for input in [
        b"nan,0\n".as_slice(),
        b"inf,0\n",
        b"1.5,2\n",
        b"2147483648,0\n",
        b"-2147483649,0\n",
        b" 1,2\n",
        b",2\n",
    ] {
        fail(
            &invoke(&[], input),
            2,
            "invalid-coordinate stage=coordinate row=0",
        );
    }
    for input in [b"1\n".as_slice(), b"\"1,2\n", b"1,\xff\n", b"1,2\n3\n"] {
        fail(&invoke(&[], input), 2, "invalid-csv stage=csv");
    }
    for args in [
        vec!["--wat"],
        vec!["operand"],
        vec!["--max-points"],
        vec!["--max-points=-1"],
        vec!["--max-points=2147483648"],
        vec!["--max-work=18446744073709551616"],
        vec!["--max-work=1", "--max-work=2"],
    ] {
        fail(&invoke(&args, b""), 2, "invalid-arguments stage=arguments");
    }
    fail(&invoke(&[], b"1,2,3\n"), 2, "resource-limit stage=csv");
    fail(
        &invoke(&["--max-input-bytes=3"], b"1,2\n"),
        2,
        "resource-limit stage=input",
    );
    fail(
        &invoke(&["--max-points=0"], b"1,2\n"),
        2,
        "resource-limit stage=csv",
    );
    fail(
        &invoke(&["--max-points=1"], b"1,2\n3,4\n"),
        2,
        "resource-limit stage=csv",
    );
    fail(
        &invoke(&["--max-work=0"], b"1,2\n"),
        2,
        "resource-limit stage=input",
    );
    fail(
        &invoke(&["--max-work=4"], b"1,2\n"),
        2,
        "resource-limit stage=hull",
    );
    fail(
        &invoke(&["--max-output-bytes=0"], b"1,2\n"),
        2,
        "resource-limit stage=output",
    );
    fail(&invoke(&[],b"-2147483648,-2147483648\n2147483647,-2147483648\n2147483647,2147483647\n-2147483648,2147483647\n"),2,"area-overflow stage=area");
    let baseline = invoke(&[], b"1,2\n");
    assert!(baseline.status.success(), "{baseline:?}");
    let exact = baseline.stdout.len().to_string();
    let tight = (baseline.stdout.len() - 1).to_string();
    let at = invoke(
        &[
            "--max-input-bytes=4",
            "--max-points=1",
            "--max-work=20",
            "--max-output-bytes",
            &exact,
        ],
        b"1,2\n",
    );
    assert!(at.status.success(), "{at:?}");
    assert_eq!(at.stdout, baseline.stdout);
    fail(
        &invoke(&["--max-output-bytes", &tight], b"1,2\n"),
        2,
        "resource-limit stage=output",
    );
    let empty = invoke(
        &["--max-points=0", "--max-work=0", "--max-input-bytes=0"],
        b"",
    );
    assert!(empty.status.success(), "{empty:?}");
    let help = invoke(&["--help"], b"");
    assert!(
        help.status.success()
            && String::from_utf8_lossy(&help.stdout).contains("Usage: shape-hull"),
        "{help:?}"
    );
    assert!(!help.stdout.contains(&0));
}
fn no_leaks(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut n = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(
                    live.insert(result.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                n += 1;
            }
        } else if let Some(rest) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(rest.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "unreleased {live:?}: {events}");
    n
}
#[test]
fn consumer_releases_all_observed_allocations_and_handles_io_faults() {
    let input = file(b"0,0\n4,0\n4,4\n0,4\n2,2\n");
    let trace = common::TempArtifact::new("laniusc_shape_hull", "trace", None);
    let execute = |fault: Option<String>| {
        let mut c = Command::new("strace");
        c.args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write"]);
        if let Some(ref f) = fault {
            c.args(["-e", &format!("inject={f}")]);
        }
        c.arg(executable().path())
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap()));
        let out = common::process_output_with_timeout(
            "shape-hull fault cleanup",
            &mut c,
            Duration::from_secs(5),
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        no_leaks(&events);
        if fault.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        (out, events)
    };
    let (baseline, events) = execute(None);
    assert!(baseline.status.success(), "{baseline:?}");
    let allocations = no_leaks(&events);
    assert!(allocations >= 6, "{events}");
    for i in 1..=allocations {
        fail(
            &execute(Some(format!("mmap:error=ENOMEM:when={i}"))).0,
            4,
            "allocation-failure",
        );
    }
    fail(
        &execute(Some("read:error=EIO:when=1".to_owned())).0,
        3,
        "io-failure stage=input",
    );
    fail(
        &execute(Some("write:error=EIO:when=1".to_owned())).0,
        3,
        "io-failure stage=output",
    );
    let (interrupted, _) = execute(Some("read:error=EINTR:when=1".to_owned()));
    assert_eq!(interrupted.status.code(), Some(0), "{interrupted:?}");
    assert_eq!(interrupted.stdout, baseline.stdout);
    let full = Command::new(executable().path())
        .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap()))
        .stdout(Stdio::from(
            std::fs::OpenOptions::new()
                .write(true)
                .open("/dev/full")
                .unwrap(),
        ))
        .output()
        .unwrap();
    assert_eq!(full.status.code(), Some(3), "{full:?}");
    assert!(String::from_utf8_lossy(&full.stderr).contains("io-failure stage=output"));
}
