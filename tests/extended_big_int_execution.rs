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
    let exe = common::TempArtifact::new("laniusc_big_int", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn signed_contracts_extrema_zero_limits_and_atomic_output() {
    let exe = executable("big_int_contracts");
    let output = common::process_output_with_timeout(
        "BigInt contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(5),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
}

#[test]
fn signed_arithmetic_radices_bitwise_and_multistep_differential_against_python() {
    // Seed and commands are deterministic. Python is only the independent test
    // oracle; the tested arithmetic runs in the compiled native Lanius binary.
    let oracle = Command::new("python3")
        .args(["-c", r#"
import random,math
rng=random.Random(0xb161a7)
digits='0123456789abcdefghijklmnopqrstuvwxyz'
def fmt(n,r):
    if n==0:return '0'
    s='-' if n<0 else '';n=abs(n);v=''
    while n:n,d=divmod(n,r);v=digits[d]+v
    return s+v
def result(op,a,b,k):
    if op==0:return [a+b]
    if op==1:return [a-b]
    if op==2:return [a*b]
    if op==3:
        q=abs(a)//abs(b)*(-1 if (a<0)!=(b<0) else 1);return [q,a-q*b]
    if op==4:
        r=a%abs(b);return [(a-r)//b,r]
    return [{5:lambda:a<<k,6:lambda:a>>k,7:lambda:a&b,8:lambda:a|b,9:lambda:a^b,10:lambda:~a,11:lambda:-a,12:lambda:(a>b)-(a<b),13:lambda:abs(a),14:lambda:a+a,15:lambda:a-a,16:lambda:a*a,17:lambda:a**k,18:lambda:math.gcd(a,b)}[op]()]
def emit(op,a,b,k,r):
    if op==17:k%=9
    values=result(op,a,b,k)
    if op in (3,4):
        q,rem=values;assert a==q*b+rem and abs(rem)<abs(b)
        if op==3:assert rem==0 or (rem<0)==(a<0)
        else:assert rem>=0
    print('\t'.join(map(str,[op,r,k,fmt(a,r),fmt(b,r),*[fmt(v,r) for v in values],fmt(a,r),fmt(b,r)])))
edges=[0,1,-1,2,-2,2**31,-2**31,2**32-1,-2**32,2**63-1,-2**63,2**64-1,-2**64,2**128+1,-2**128-1,2**1024-1,-2**1024]
for a in edges:
    for b in edges:
        for op in range(19):
            if op in (3,4) and not b:continue
            emit(op,a,b,rng.choice([0,1,31,32,33,63,64,65,1024,2048]),rng.choice([2,8,10,16,36]))
for i in range(320):
    a=rng.getrandbits(rng.choice([1,31,32,33,64,65,127,128,257,1023,2048]));b=rng.getrandbits(rng.randrange(1,1025))
    if rng.randrange(2):a=-a
    if rng.randrange(2):b=-b
    op=rng.randrange(19)
    if op in (3,4) and not b:b=1
    emit(op,a,b,rng.randrange(0,2300),rng.randrange(2,37))
for radix in range(2,37):
    for op in range(19):emit(op,-2**160-17,2**96+3,3,radix)
state=-2**192+17
for i in range(180):
    op=rng.choice([0,1,2,4,6,7,8,9,10,11]);b=rng.randrange(-2**40,2**40) or 1;k=rng.randrange(0,19)
    emit(op,state,b,k,10);state=result(op,state,b,k)[0]
"#])
        .output()
        .expect("Python integer reference");
    assert!(oracle.status.success(), "{oracle:?}");
    let text = String::from_utf8(oracle.stdout).unwrap();
    let mut packet = Vec::new();
    let mut expected = Vec::new();
    for line in text.lines() {
        let fields: Vec<_> = line.split('\t').collect();
        let op: u8 = fields[0].parse().unwrap();
        let radix: u8 = fields[1].parse().unwrap();
        let shift: u16 = fields[2].parse().unwrap();
        let a = fields[3].as_bytes();
        let b = fields[4].as_bytes();
        packet.extend_from_slice(&[op, radix]);
        packet.extend_from_slice(&(a.len() as u16).to_le_bytes());
        packet.extend_from_slice(&(b.len() as u16).to_le_bytes());
        packet.extend_from_slice(&shift.to_le_bytes());
        packet.extend_from_slice(a);
        packet.extend_from_slice(b);
        for value in &fields[5..] {
            expected.push((line.to_owned(), value.as_bytes().to_vec()));
        }
    }
    let input = common::TempArtifact::new("laniusc_big_int", "model_input", None);
    input.write_bytes(packet);
    let exe = executable("big_int_model");
    let output = common::process_output_with_timeout(
        "BigInt Python differential seed 0xb161a7",
        Command::new(exe.path()).stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(40),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let mut bytes = output.stdout.as_slice();
    for (case, expected) in expected {
        assert!(bytes.len() >= 4, "Missing result: {case}");
        let count = u32::from_le_bytes(bytes[..4].try_into().unwrap()) as usize;
        bytes = &bytes[4..];
        assert!(count <= bytes.len(), "Truncated result: {case}");
        assert_eq!(&bytes[..count], expected, "{case}");
        bytes = &bytes[count..];
    }
    assert!(bytes.is_empty());
}

fn trace_run(exe: &common::TempArtifact, op: u8, failure: Option<usize>) -> String {
    let input = common::TempArtifact::new("laniusc_big_int", "alloc_op", None);
    input.write_bytes([op]);
    let trace = common::TempArtifact::new("laniusc_big_int", "alloc_trace", None);
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
        format!("BigInt operation {op}, allocation failure {failure:?}"),
        &mut command,
        Duration::from_secs(5),
    );
    assert_eq!(
        output.status.code(),
        Some(0),
        "op={op} failure={failure:?}: {output:?}"
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
            assert!(live.remove(address), "Unowned free: {text}");
            assert!(line.ends_with("= 0"), "{text}");
        }
    }
    assert!(live.is_empty(), "Leaked allocations: {live:?}\n{text}");
    text
}

#[test]
fn every_observed_allocation_failure_preserves_operands_and_releases_temporary_owners() {
    let exe = executable("big_int_allocation_failure");
    for op in 0..31 {
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
