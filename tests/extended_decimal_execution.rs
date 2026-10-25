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
    let exe = common::TempArtifact::new("laniusc_decimal", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[test]
fn decimal_contracts_limits_and_atomic_output() {
    let exe = executable("decimal_arithmetic_contracts");
    let output = common::process_output_with_timeout(
        "Decimal contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
#[test]
fn decimal_arithmetic_and_all_rounding_modes_against_python_decimal_and_fraction() {
    let oracle = Command::new("python3").args(["-c",r#"
from decimal import *
from fractions import Fraction
import random
rng=random.Random(0xdec1a1)
roundings=[ROUND_DOWN,ROUND_UP,ROUND_FLOOR,ROUND_CEILING,ROUND_HALF_UP,ROUND_HALF_DOWN,ROUND_HALF_EVEN,ROUND_DOWN]
def canon(x):
    if not x: x=x.copy_abs()
    t=x.as_tuple();s='-' if t.sign else '';d=''.join(map(str,t.digits));e=t.exponent+len(d)-1
    sci=s+d[0]+('.'+d[1:] if len(d)>1 else '')+'E'+('+' if e>=0 else '-')+str(abs(e))
    return sci+'\t'+format(x,'f')
def emit(op,aa,bb='1',mode=6,p=34,arg=0):
    a,b=Decimal(aa),Decimal(bb);status=0
    with localcontext() as c:
        c.prec=20000;c.Emax=100000;c.Emin=-100000;c.rounding=roundings[mode]
        try:
            if op in (3,5,10):c.prec=p
            if mode==7:c.traps[Inexact]=True
            if op==0:r=a+b;assert Fraction(r)==Fraction(a)+Fraction(b)
            elif op==1:r=a-b;assert Fraction(r)==Fraction(a)-Fraction(b)
            elif op==2:r=a*b;assert Fraction(r)==Fraction(a)*Fraction(b)
            elif op==3:r=a/b
            elif op==4:r=a.quantize(Decimal((0,(1,),arg)))
            elif op==5:r=+a
            elif op==6:r=Decimal(1) if arg==0 else (Decimal((0,(0,),a.as_tuple().exponent*arg)) if not a else a**arg)
            elif op==7:r=a.copy_negate()
            elif op==8:r=a.copy_abs()
            elif op==9:r=a.normalize()
            elif op==10:r=a.quantize(b)
            elif op==11:r=a
            elif op==12:r=Decimal((a>b)-(a<b))
            elif op==13:r=a+a
            elif op==14:r=a-a
            elif op==15:r=a*a
            if op==5 and not a:r=Decimal((0,(0,),a.as_tuple().exponent))
        except Inexact:status=11
        except DivisionByZero:status=10
        except InvalidOperation:status=4
    output=[] if status else canon(r).split('\t')
    print('\t'.join(map(str,[op,mode,p,arg,aa,bb,status,*output,*canon(a).split('\t'),*canon(b).split('\t')])))
edges=['0','-0.00','0E+5','1','-1','1.20','12.00','0.00125','-0.00125','2.5','-2.5','3.5','-3.5','9.9995','99999.5','1E-35','-1E+35','100000000000000000000000000000000000000000000001','-99999999999999999999999999999999999999999999999']
for a in edges:
    for b in edges:
        for op in (0,1,2,12,13,14,15):emit(op,a,b)
        if Decimal(b):
            for m in range(8):emit(3,a,b,m,rng.choice([1,2,5,16,34,64]))
for a in edges+['2.4500','2.45001','2.44999','-2.4500','-2.45001','-2.44999','9.95','-9.95']:
    for m in range(8):
        for e in [-20,-4,-2,-1,0,1,4,20]:emit(4,a,mode=m,arg=e)
        for p in [1,2,3,10,34]:emit(5,a,mode=m,p=p)
        for q in ['1','0.01','1E+3']:emit(10,a,q,m,p=8)
    for op in [7,8,9,11]:emit(op,a)
    for n in [0,1,2,3,7]:emit(6,a,arg=n)
for i in range(500):
    def operand():
        n=rng.getrandbits(rng.choice([1,32,64,127,257,1024]));n=-n if rng.randrange(2) else n
        return str(n)+'E'+str(rng.randrange(-100,101))
    a,b=operand(),operand();op=rng.randrange(16);m=rng.randrange(8);p=rng.randrange(1,90);arg=rng.randrange(-100,101)
    if op==3 and not Decimal(b):b='1'
    if op==6:arg=rng.randrange(0,6)
    emit(op,a,b,m,p,arg)
# Cancellation across thousands of digits and comparison with different quantum.
emit(0,'9'*1500,'-'+('9'*1499)+'8')
emit(1,'1E+1500','1')
emit(3,'1','7',6,1024)
emit(3,'1E-999','8',6,1024)
"#]).output().expect("Python Decimal/Fraction oracle");
    assert!(oracle.status.success(), "{oracle:?}");
    let text = String::from_utf8(oracle.stdout).unwrap();
    let mut packet = Vec::new();
    let mut expected = Vec::new();
    for line in text.lines() {
        let f: Vec<_> = line.split('\t').collect();
        let op: u8 = f[0].parse().unwrap();
        let mode: u8 = f[1].parse().unwrap();
        let p: u16 = f[2].parse().unwrap();
        let arg: i32 = f[3].parse().unwrap();
        packet.extend_from_slice(&[op, mode]);
        packet.extend_from_slice(&p.to_le_bytes());
        packet.extend_from_slice(&arg.to_le_bytes());
        for operand in &f[4..6] {
            packet.extend_from_slice(&(operand.len() as i32).to_le_bytes());
        }
        for operand in &f[4..6] {
            packet.extend_from_slice(operand.as_bytes());
        }
        expected.push((
            line.to_owned(),
            f[6].parse::<u32>().unwrap(),
            f[7..]
                .iter()
                .map(|s| s.as_bytes().to_vec())
                .collect::<Vec<_>>(),
        ));
    }
    let input = common::TempArtifact::new("laniusc_decimal", "model_input", None);
    input.write_bytes(packet);
    let exe = executable("decimal_arithmetic_model");
    let output = common::process_output_with_timeout(
        "Decimal differential seed 0xdec1a1",
        Command::new(exe.path()).stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(60),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let mut bytes = output.stdout.as_slice();
    for (case, status, frames) in expected {
        assert!(bytes.len() >= 4, "Missing status: {case}");
        let actual = u32::from_le_bytes(bytes[..4].try_into().unwrap());
        bytes = &bytes[4..];
        assert_eq!(actual, status, "{case}");
        for frame in frames {
            assert!(bytes.len() >= 4, "Missing frame: {case}");
            let n = u32::from_le_bytes(bytes[..4].try_into().unwrap()) as usize;
            bytes = &bytes[4..];
            assert!(n <= bytes.len(), "Truncated frame: {case}");
            assert_eq!(&bytes[..n], frame, "{case}");
            bytes = &bytes[n..];
        }
    }
    assert!(bytes.is_empty());
}
fn trace_run(exe: &common::TempArtifact, op: u8, failure: Option<usize>) -> String {
    let input = common::TempArtifact::new("laniusc_decimal", "allocation_op", None);
    input.write_bytes([op]);
    let trace = common::TempArtifact::new("laniusc_decimal", "allocation_trace", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"]);
    if let Some(index) = failure {
        command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={index}")]);
    }
    let output = common::process_output_with_timeout(
        format!("Decimal operation {op}, failure {failure:?}"),
        command
            .arg(exe.path())
            .stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(5),
    );
    assert_eq!(
        output.status.code(),
        Some(0),
        "op={op}, failure={failure:?}: {output:?}"
    );
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
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
    assert!(live.is_empty(), "Leaked decimal owners: {live:?}\n{text}");
    text
}
#[test]
fn every_observed_decimal_allocation_failure_preserves_operands_and_releases_owners() {
    let exe = executable("decimal_arithmetic_faults");
    for op in 0..23 {
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
