#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::{ffi::OsStrExt, fs::PermissionsExt},
    process::{Command, Output, Stdio},
    time::{Duration, Instant},
};
fn executable() -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/data_analyze.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("data-analyze", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("data-analyze: {e}"));
    let exe = common::TempArtifact::new("laniusc_data_analyze", "executable", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(c: &mut Command) -> Output {
    common::process_output_with_timeout("data-analyze", c, Duration::from_secs(20))
}
fn file(bytes: &[u8]) -> common::TempArtifact {
    let data = common::TempArtifact::new("laniusc_data_analyze", "data", None);
    data.write_bytes(bytes);
    data
}
fn invoke(exe: &common::TempArtifact, args: &[&str], bytes: &[u8]) -> Output {
    let input = file(bytes);
    run(Command::new(exe.path())
        .args(args)
        .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())))
}
fn success(o: &Output) {
    assert_eq!(o.status.code(), Some(0), "{o:?}");
    assert!(o.stderr.is_empty(), "{o:?}");
}
fn failure(o: &Output, status: i32, reason: &str) {
    assert_eq!(o.status.code(), Some(status), "{o:?}");
    assert!(o.stdout.is_empty(), "{o:?}");
    let d = std::str::from_utf8(&o.stderr).unwrap();
    assert!(
        d.starts_with("data-analyze: ") && d.ends_with('\n') && d.contains(reason),
        "{d}"
    );
}
fn oracle(input: &[u8], output: &[u8], header: bool, fit: bool, intercept: bool) {
    let input = file(input);
    let output = file(output);
    // These host libraries are independent test oracles only. Production parses,
    // summarizes, sorts, factors and formats using Lanius library code.
    let script = r#"import csv,math,statistics,sys
import numpy as np
src=list(csv.reader(open(sys.argv[1],newline='',encoding='utf-8')))
header,fit,intercept=map(int,sys.argv[3:]); names=src.pop(0) if header else ['']*len(src[0])
data=[[float(x) for x in row] for row in src]
rows=list(csv.reader(open(sys.argv[2],newline='',encoding='utf-8')))
assert rows.pop(0)==['record','column','name','metric','value']
assert all(len(r)==5 and math.isfinite(float(r[4])) for r in rows),rows
expected=[]
def eq(a,b,rel=3e-12,absolute=5e-324):
 assert math.isclose(a,b,rel_tol=rel,abs_tol=absolute),(a,b)
for c,name in enumerate(names):
 v=[row[c] for row in data]
 metrics=[('count',len(v)),('mean',statistics.mean(v))]
 if len(v)>1: metrics.append(('sample_sd',statistics.stdev(v)))
 metrics += [('min',min(v)),('max',max(v)),('median',statistics.median(v))]
 for key,value in metrics:
  r=rows.pop(0);assert r[:4]==['column',str(c),name,key],r;eq(float(r[4]),value)
if fit:
 a=np.array([r[:-1] for r in data],dtype=np.float64);y=np.array([r[-1] for r in data],dtype=np.float64)
 if intercept: a=np.column_stack((np.ones(len(data)),a))
 estimates,resid,rank,s=np.linalg.lstsq(a,y,rcond=1e-12)
 assert rank==a.shape[1]
 actual=[]
 for c,value in enumerate(estimates):
  index=c-int(intercept);name='intercept' if index==-1 else names[index]
  r=rows.pop(0);assert r[:4]==['coefficient',str(index),name,'estimate'],r
  actual.append(float(r[4]));eq(actual[-1],value,rel=3e-7,absolute=2e-7)
 residual=y-a@np.array(actual);norm=float(np.linalg.norm(residual))
 for key,value in [('observations',len(data)),('parameters',len(estimates)),('residual_dof',len(data)-len(estimates)),('residual_norm',norm),('residual_sum_squares',norm*norm),('rmse',norm/math.sqrt(len(data)))]:
  r=rows.pop(0);assert r[:4]==['fit','','',key],r;eq(float(r[4]),value,rel=3e-7,absolute=2e-11)
assert not rows,rows
"#;
    let result = run(Command::new("python3")
        .args(["-c", script])
        .arg(input.path())
        .arg(output.path())
        .arg(u8::from(header).to_string())
        .arg(u8::from(fit).to_string())
        .arg(u8::from(intercept).to_string()));
    assert!(
        result.status.success() && result.stderr.is_empty(),
        "oracle: {}",
        String::from_utf8_lossy(&result.stderr)
    );
}
#[test]
fn data_analyze_matches_independent_csv_statistics_and_qr_oracles() {
    let exe = executable();
    for (args, input, header, fit, intercept) in [
        (vec![], "1,9\n3,7\n3,7\n-5,11\n", false, false, true),
        (
            vec!["--header"],
            "\"é,🙂\",\"quote\"\" and\nline\"\r\n.5,1.\n+3e0,-0\n2.5,4",
            true,
            false,
            true,
        ),
        (vec![], "5e-324,-0\n0,0\n-5e-324,0\n", false, false, true),
        (vec!["--header"], "one,two\n-0,1e308\n", true, false, true),
        (
            vec!["--header", "--fit"],
            "x,y\n1,3\n2,5\n3,7\n",
            true,
            true,
            true,
        ),
        (
            vec!["--fit", "--no-intercept"],
            "1,3\n2,6\n3,9\n",
            false,
            true,
            false,
        ),
        (vec!["--fit"], "0,1\n1,3\n", false, true, true),
    ] {
        let out = invoke(&exe, &args, input.as_bytes());
        success(&out);
        oracle(input.as_bytes(), &out.stdout, header, fit, intercept);
        assert_eq!(
            invoke(&exe, &args, input.as_bytes()).stdout,
            out.stdout,
            "deterministic format"
        );
    }
    let mut source = String::from("first,near_first,sign,response\r\n");
    for row in 0..4096 {
        let x = row as f64 / 64.0 - 32.0;
        let z = x + (row % 17) as f64 * 0.00001;
        let sign = if row % 2 == 0 { 1.0 } else { -1.0 };
        let y = 2.0 + 3.0 * x - 4.0 * z + 0.25 * sign + (row % 7) as f64 * 0.000001;
        source.push_str(&format!("{x:.17},{z:.17},{sign},{y:.17}\n"));
    }
    let start = Instant::now();
    let out = invoke(&exe, &["--header", "--fit"], source.as_bytes());
    let elapsed = start.elapsed();
    success(&out);
    oracle(source.as_bytes(), &out.stdout, true, true, true);
    eprintln!(
        "data-analyze: 4096×4, {} input bytes / {} output bytes, {:.3}ms native process and file I/O, compilation excluded",
        source.len(),
        out.stdout.len(),
        elapsed.as_secs_f64() * 1000.0
    );
}
#[test]
fn data_analyze_rejects_bad_numbers_csv_shapes_rank_and_resource_limits_atomically() {
    let exe = executable();
    for (args, input, reason) in [
        (vec![], b"".as_slice(), "empty-data"),
        (vec!["--header"], b"x,y\n", "empty-data"),
        (
            vec![],
            b"1,2\n3,4\n5,no\n",
            "invalid-number stage=number row=2 column=1",
        ),
        (vec![], b"1,NaN\n", "nonfinite-number"),
        (vec![], b"1,inf\n", "nonfinite-number"),
        (vec![], b"1,1e999\n", "nonfinite-number"),
        (vec![], b"1, 2\n", "invalid-number"),
        (vec![], b"1,\n", "invalid-number"),
        (vec![], b"1,2\n3\n", "shape-error"),
        (vec![], b"1,2\n3,4,5\n", "shape-error"),
        (vec![], b"1,2\n\"unfinished", "csv-error"),
        (vec![], b"1,\xff\n", "invalid-utf8 stage=input byte=2"),
        (vec!["--fit"], b"1,2\n1,3\n1,4\n", "rank-deficient"),
        (vec!["--fit"], b"1,2,3\n2,3,4\n", "shape-error"),
        (vec!["--fit"], b"1\n2\n", "shape-error"),
        (vec![], b"1e308\n-1e308\n", "numerical-failure"),
        (vec!["--max-input-bytes=3"], b"1,2\n", "resource-limit"),
        (vec!["--max-rows=1"], b"1\n2\n", "resource-limit"),
        (vec!["--max-columns=1"], b"1,2\n", "resource-limit"),
        (vec!["--max-elements=3"], b"1,2\n3,4\n", "resource-limit"),
        (
            vec!["--max-output-bytes=4"],
            b"1\n",
            "resource-limit stage=output",
        ),
        (vec!["--max-work=0"], b"1\n", "resource-limit"),
        (vec!["--max-work=999999"], b"1\n", "resource-limit"),
    ] {
        failure(&invoke(&exe, &args, input), 2, reason);
    }
    failure(
        &invoke(&exe, &["--max-work=1000000"], b"1\n"),
        2,
        "resource-limit stage=summary column=0",
    );
    failure(
        &invoke(&exe, &["--fit", "--max-work=18000192"], b"1,3\n2,5\n3,7\n"),
        2,
        "resource-limit stage=fit",
    );
    let long_header = format!("{}🙂,response\n1,2\n2,4\n", "a".repeat(1020));
    let out = invoke(&exe, &["--header"], long_header.as_bytes());
    success(&out);
    oracle(long_header.as_bytes(), &out.stdout, true, false, true);
    let too_many_digits = format!("{}.0\n", "1".repeat(769));
    failure(
        &invoke(&exe, &[], too_many_digits.as_bytes()),
        2,
        "resource-limit stage=number row=0 column=0",
    );
    let oversized_header = format!("{}🙂,response\n1,2\n", "a".repeat(1021));
    failure(
        &invoke(&exe, &["--header"], oversized_header.as_bytes()),
        2,
        "resource-limit",
    );
    for bad in [b"1,\xc0\x80".as_slice(), b"1,\xed\xa0\x80", b"1,\xf0\x9f"] {
        failure(
            &invoke(&exe, &[], bad),
            2,
            "invalid-utf8 stage=input byte=2",
        );
    }
    for args in [
        vec!["--wat"],
        vec!["file.csv"],
        vec!["--header", "--header"],
        vec!["--no-intercept"],
        vec!["--help", "--fit"],
        vec!["--max-columns=0"],
        vec!["--max-columns=257"],
        vec!["--max-rows=1000001"],
        vec!["--max-elements=8000001"],
        vec!["--max-input-bytes=-1"],
        vec!["--max-work=+1"],
        vec!["--max-work=18446744073709551616"],
        vec!["--max-output-bytes=16777217"],
        vec!["--max-work"],
    ] {
        failure(&invoke(&exe, &args, b""), 2, "invalid-arguments");
    }
    failure(
        &invoke(&exe, &vec!["--header"; 33], b""),
        2,
        "invalid-arguments",
    );
    failure(
        &invoke(&exe, &[&"x".repeat(8193)], b""),
        2,
        "invalid-arguments",
    );
    failure(
        &run(Command::new(exe.path()).arg(std::ffi::OsStr::from_bytes(b"--max-work=\xff"))),
        2,
        "invalid-arguments",
    );
    let help = invoke(&exe, &["--help"], b"\xff");
    success(&help);
    assert!(help.stdout.starts_with(b"Usage: data-analyze ") && help.stdout.ends_with(b"\n"));
    let exact = invoke(&exe, &[], b"1\n");
    success(&exact);
    success(&invoke(
        &exe,
        &[
            &format!("--max-output-bytes={}", exact.stdout.len()),
            "--max-input-bytes=2",
            "--max-rows=1",
            "--max-columns=1",
            "--max-elements=1",
        ],
        b"1\n",
    ));
    failure(
        &invoke(
            &exe,
            &[&format!("--max-output-bytes={}", exact.stdout.len() - 1)],
            b"1\n",
        ),
        2,
        "resource-limit",
    );
}
fn no_leaks(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(
                    live.insert(result.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "unreleased allocations: {events}");
    count
}
#[test]
fn data_analyze_releases_every_observed_allocation_and_handles_host_io_faults() {
    let exe = executable();
    let input = file(b"x,z,y\n1,2,5\n2,-1,0\n3,0,3\n4,4,12\n5,-3,-2\n");
    let trace = common::TempArtifact::new("laniusc_data_analyze", "trace", None);
    let execute = |fault: Option<&str>| {
        let mut c = Command::new("strace");
        c.args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write"]);
        if let Some(f) = fault {
            c.arg("-e").arg(format!("inject={f}"));
        }
        let out = run(c
            .arg(exe.path())
            .args(["--header", "--fit", "--max-output-bytes=4096"])
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
        let events = std::fs::read_to_string(trace.path()).unwrap();
        no_leaks(&events);
        if fault.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        (out, events)
    };
    let (baseline, events) = execute(None);
    success(&baseline);
    let allocations = no_leaks(&events);
    assert!(allocations >= 10, "{events}");
    for when in 1..=allocations {
        failure(
            &execute(Some(&format!("mmap:error=ENOMEM:when={when}"))).0,
            4,
            "allocation-failure",
        );
    }
    let reads = events.lines().filter(|l| l.starts_with("read(")).count();
    for when in 1..=reads {
        failure(
            &execute(Some(&format!("read:error=EIO:when={when}"))).0,
            3,
            "io-failure stage=input",
        );
    }
    let writes = events.lines().filter(|l| l.starts_with("write(")).count();
    for when in 1..=writes {
        for f in [
            format!("write:error=EIO:when={when}"),
            format!("write:retval=0:when={when}"),
        ] {
            let (out, _) = execute(Some(&f));
            assert_eq!(out.status.code(), Some(3), "{out:?}");
            assert!(
                String::from_utf8_lossy(&out.stderr).contains("io-failure stage=output"),
                "{out:?}"
            );
            assert!(baseline.stdout.starts_with(&out.stdout));
        }
    }
    for f in ["read:error=EINTR:when=1", "write:error=EINTR:when=1"] {
        let (out, _) = execute(Some(f));
        success(&out);
        assert_eq!(out.stdout, baseline.stdout);
    }
    let (short, _) = execute(Some("write:retval=17:when=1"));
    success(&short);
    assert_eq!(short.stdout, baseline.stdout[17..]);
    for bad in [
        b"x,y\n1,2\n3,bad\n".as_slice(),
        b"x,y\n1,2\n\"open",
        b"x,y\n1,2\n1,3\n",
    ] {
        input.write_bytes(bad);
        failure(
            &execute(None).0,
            2,
            if bad.ends_with(b"1,3\n") {
                "rank-deficient"
            } else if bad.ends_with(b"open") {
                "csv-error"
            } else {
                "invalid-number"
            },
        );
    }
    let full = run(Command::new("sh")
        .args(["-c", "exec \"$1\" <\"$2\" >/dev/full", "data-analyze"])
        .arg(exe.path())
        .arg(file(b"1\n2\n").path()));
    failure(&full, 3, "io-failure stage=output");
    let out = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap,write",
            "-e",
            "inject=write:error=EIO:when=1",
        ])
        .arg(exe.path())
        .arg("--bad"));
    assert_eq!(out.status.code(), Some(3));
    assert!(out.stdout.is_empty() && out.stderr.is_empty());
    no_leaks(&std::fs::read_to_string(trace.path()).unwrap());
    let out = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap,write",
            "-e",
            "inject=write:error=EIO:when=1",
        ])
        .arg(exe.path())
        .arg("--help"));
    failure(&out, 3, "io-failure stage=output");
    no_leaks(&std::fs::read_to_string(trace.path()).unwrap());
}
