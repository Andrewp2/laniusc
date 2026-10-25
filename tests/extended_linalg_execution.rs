#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};

fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/extended_library/{name}.lani"));
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
    let exe = common::TempArtifact::new("laniusc_linalg", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn matrix_lu_qr_views_shapes_numerical_boundaries_and_limits() {
    let exe = executable("linalg_contracts");
    let output = common::process_output_with_timeout(
        "matrix, pivoted LU and Householder QR contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(5),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
}

#[derive(Debug)]
struct Case {
    op: i32,
    m: usize,
    n: usize,
    p: usize,
    a: Vec<f64>,
    b: Vec<f64>,
    expected: Vec<f64>,
}
fn floats(text: &str) -> Vec<f64> {
    text.split_whitespace()
        .map(|v| v.parse().unwrap())
        .collect()
}
fn scalar(bytes: &mut &[u8]) -> f64 {
    assert!(bytes.len() >= 8, "truncated scalar");
    let value = f64::from_le_bytes(bytes[..8].try_into().unwrap());
    *bytes = &bytes[8..];
    assert!(value.is_finite(), "nonfinite result");
    value
}
fn matrix(bytes: &mut &[u8], rows: usize, cols: usize) -> Vec<f64> {
    assert!(bytes.len() >= 8, "truncated shape");
    let r = i32::from_le_bytes(bytes[..4].try_into().unwrap());
    let c = i32::from_le_bytes(bytes[4..8].try_into().unwrap());
    *bytes = &bytes[8..];
    assert_eq!((r, c), (rows as i32, cols as i32));
    let mut values: Vec<_> = (0..rows * cols).map(|_| scalar(bytes)).collect();
    values.reverse(); // Lanius typed f64 storage is descending.
    values
}
fn close(actual: f64, expected: f64, context: &str) {
    assert!(
        (actual - expected).abs() <= 2e-9 * expected.abs().max(1.0),
        "{context}: {actual} != {expected}"
    );
}

#[test]
fn native_matrix_arithmetic_matches_fraction_and_numpy_and_satisfies_decomposition_properties() {
    // Only this test oracle uses Python/NumPy. Production arithmetic executes
    // in the compiled native Lanius program; transport contains raw f64 values.
    let oracle = Command::new("python3")
        .args([
            "-c",
            r#"
from fractions import Fraction as F
import random, math
rng=random.Random(0x1a119)
def emit(op,m,n,p,a,b,expected):
    def text(v):return ' '.join(repr(float(x)) for x in v)
    print(f'{op} {m} {n} {p}|{text(a)}|{text(b)}|{text(expected)}')
def solve(a,b):
    n=len(a);p=len(b[0]);v=[[F(x) for x in a[i]+b[i]] for i in range(n)]
    for k in range(n):
        pivot=next(i for i in range(k,n) if v[i][k]);v[k],v[pivot]=v[pivot],v[k]
        q=v[k][k];v[k]=[x/q for x in v[k]]
        for i in range(n):
            if i!=k:
                q=v[i][k];v[i]=[x-q*y for x,y in zip(v[i],v[k])]
    return [row[n:] for row in v]
def det(a):
    n=len(a)
    if n==1:return F(a[0][0])
    return sum((-1)**j*F(a[0][j])*det([r[:j]+r[j+1:] for r in a[1:]]) for j in range(n))
def flat(a):return [v for row in a for v in row]
for n in range(1,5):
    for trial in range(10):
        a=[[rng.randint(-4,4)+(10 if i==j else 0) for j in range(n)] for i in range(n)]
        rng.shuffle(a)
        b=[[rng.randint(-8,8) for _ in range(3)] for i in range(n)]
        unit=[[int(i==j) for j in range(n)] for i in range(n)]
        emit(1,n,n,3,flat(a),flat(b),flat(solve(a,b)))
        emit(2,n,n,n,flat(a),[],flat(solve(a,unit)))
        emit(4,n,n,1,flat(a),[],[det(a)])
for trial in range(50):
    m,n,p=[rng.randrange(1,8) for _ in range(3)]
    a=[rng.randrange(-8,9) for _ in range(m*n)];b=[rng.randrange(-8,9) for _ in range(n*p)]
    expected=[sum(F(a[i*n+k])*F(b[k*p+j]) for k in range(n)) for i in range(m) for j in range(p)]
    emit(0,m,n,p,a,b,expected)
try:
    import numpy as np
except ImportError:
    np=None
if np is not None:
    nr=np.random.default_rng(0x1a119)
    for trial in range(75):
        n=1+trial%5;m=n+trial%7;p=1+trial%3
        a=nr.normal(size=(m,n));a[:n,:]+=np.eye(n)*3
        b=nr.normal(size=(m,p))
        expected=np.linalg.lstsq(a,b,rcond=None)[0]
        emit(3,m,n,p,a.ravel(),b.ravel(),expected.ravel())
        if trial%3==0:emit(6,m,n,1,a.ravel(),[],[])
    # Column scaling and a noisy intercept/slope fit stress a different
    # condition range without forming A^T A in the implementation.
    a=nr.normal(size=(10,3))*np.array([1e-4,1.,1e4]);b=nr.normal(size=(10,2))
    emit(3,10,3,2,a.ravel(),b.ravel(),np.linalg.lstsq(a,b,rcond=None)[0].ravel())
for scale in [1e-300,1e-200,1.,1e200,1e300]:
    a=[3*scale,4*scale]
    emit(5,2,1,1,a,[],[5*scale])
"#,
        ])
        .output()
        .expect("Python Fraction reference");
    assert!(oracle.status.success(), "{oracle:?}");
    let text = String::from_utf8(oracle.stdout).unwrap();
    let mut cases = Vec::new();
    let mut packet = Vec::new();
    for line in text.lines() {
        let fields: Vec<_> = line.split('|').collect();
        let header: Vec<i32> = fields[0]
            .split_whitespace()
            .map(|v| v.parse().unwrap())
            .collect();
        let case = Case {
            op: header[0],
            m: header[1] as usize,
            n: header[2] as usize,
            p: header[3] as usize,
            a: floats(fields[1]),
            b: floats(fields[2]),
            expected: floats(fields[3]),
        };
        for v in header {
            packet.extend_from_slice(&v.to_le_bytes());
        }
        for v in case.a.iter().chain(case.b.iter()).rev() {
            packet.extend_from_slice(&v.to_le_bytes());
        }
        cases.push(case);
    }
    let input = common::TempArtifact::new("laniusc_linalg", "oracle_input", None);
    input.write_bytes(packet);
    let exe = executable("linalg_model");
    let output = common::process_output_with_timeout(
        "linear algebra Fraction/NumPy seed 0x1a119",
        Command::new(exe.path()).stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(15),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty());
    let mut bytes = output.stdout.as_slice();
    for (index, case) in cases.iter().enumerate() {
        let label = format!("seed 0x1a119 case {index}: {case:?}");
        if case.op == 4 || case.op == 5 {
            let actual = scalar(&mut bytes);
            if case.op == 5 {
                assert!(
                    (actual / case.expected[0] - 1.0).abs() < 1e-13,
                    "{label}: {actual}"
                );
            } else {
                close(actual, case.expected[0], &label);
            }
            continue;
        }
        if case.op == 6 {
            let q = matrix(&mut bytes, case.m, case.m);
            let r = matrix(&mut bytes, case.m, case.n);
            for i in 0..case.m {
                for j in 0..case.m {
                    let dot: f64 = (0..case.m)
                        .map(|k| q[k * case.m + i] * q[k * case.m + j])
                        .sum();
                    close(dot, if i == j { 1.0 } else { 0.0 }, &label);
                }
            }
            for i in 0..case.m {
                for j in 0..case.n {
                    let value: f64 = (0..case.m)
                        .map(|k| q[i * case.m + k] * r[k * case.n + j])
                        .sum();
                    close(value, case.a[i * case.n + j], &label);
                }
            }
            continue;
        }
        let (rows, cols) = match case.op {
            0 => (case.m, case.p),
            1 | 3 => (case.n, case.p),
            2 => (case.n, case.n),
            _ => panic!("{label}"),
        };
        let result = matrix(&mut bytes, rows, cols);
        assert_eq!(result.len(), case.expected.len(), "{label}");
        for (&actual, &expected) in result.iter().zip(&case.expected) {
            close(actual, expected, &label);
        }
        if case.op == 1 || case.op == 3 {
            let mut residual = vec![0.0; case.m * case.p];
            for i in 0..case.m {
                for j in 0..case.p {
                    residual[i * case.p + j] = (0..case.n)
                        .map(|k| case.a[i * case.n + k] * result[k * case.p + j])
                        .sum::<f64>()
                        - case.b[i * case.p + j];
                }
            }
            if case.op == 1 {
                for v in residual {
                    close(v, 0.0, &label);
                }
            } else {
                for i in 0..case.n {
                    for j in 0..case.p {
                        let dot: f64 = (0..case.m)
                            .map(|k| case.a[k * case.n + i] * residual[k * case.p + j])
                            .sum();
                        let scale: f64 = (0..case.m)
                            .map(|k| (case.a[k * case.n + i] * case.b[k * case.p + j]).abs())
                            .sum();
                        assert!(
                            dot.abs() <= 2e-9 * scale.max(1.0),
                            "normal residual property {label}: {dot}"
                        );
                    }
                }
            }
        }
    }
    assert!(bytes.is_empty());
}

fn trace_run(exe: &common::TempArtifact, op: u8, failure: Option<usize>) -> String {
    let input = common::TempArtifact::new("laniusc_linalg", "alloc_op", None);
    input.write_bytes([op]);
    let trace = common::TempArtifact::new("laniusc_linalg", "alloc_trace", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"]);
    if let Some(index) = failure {
        command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={index}")]);
    }
    command
        .arg(exe.path())
        .stdin(std::fs::File::open(input.path()).unwrap());
    let output = common::process_output_with_timeout(
        format!("linalg op {op}, mmap failure {failure:?}"),
        &mut command,
        Duration::from_secs(5),
    );
    assert_eq!(
        output.status.code(),
        Some(0),
        "op={op}, failure={failure:?}: {output:?}"
    );
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
    let text = std::fs::read_to_string(trace.path()).unwrap();
    let mut live = std::collections::HashSet::new();
    for line in text.lines() {
        if line.starts_with("mmap(") && !line.contains("= -1") {
            let address = line.split(" = ").nth(1).unwrap().trim();
            assert!(live.insert(address.to_owned()), "{text}");
        } else if line.starts_with("munmap(") {
            let address = line
                .trim_start_matches("munmap(")
                .split(',')
                .next()
                .unwrap();
            assert!(live.remove(address), "unowned free: {text}");
            assert!(line.ends_with("= 0"), "{text}");
        }
    }
    assert!(live.is_empty(), "leaked allocations: {live:?}\n{text}");
    text
}

#[test]
fn every_observed_mmap_denial_releases_temporaries_and_preserves_matrix_and_factor_owners() {
    let exe = executable("linalg_allocation_failure");
    for op in 0..18 {
        let baseline = trace_run(&exe, op, None);
        let count = baseline
            .lines()
            .filter(|line| line.starts_with("mmap("))
            .count();
        assert!(count >= 2, "{op}: {baseline}");
        for index in 1..=count {
            let trace = trace_run(&exe, op, Some(index));
            assert!(trace.contains("INJECTED"), "{op}, {index}: {trace}");
        }
    }
}
