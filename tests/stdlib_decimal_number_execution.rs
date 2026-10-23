#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    time::Duration,
};

fn fixture(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let label = format!("tests/fixtures/stdlib_foundation/decimal_number_{name}.lani");
    let entry = root.join(&label);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(&label, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{label}: {error}"));
    let artifact = common::TempArtifact::new("laniusc_decimal_number", name, None);
    artifact.write_bytes(&bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("exact decimal numbers", command, Duration::from_secs(10))
}
fn check(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn integers(output: &[u8]) -> Vec<i32> {
    std::str::from_utf8(output)
        .unwrap()
        .split_whitespace()
        .map(|value| value.parse().unwrap())
        .collect()
}

#[test]
fn exact_decimals_execute_contracts_errors_views_and_exact_work_budgets_without_allocation() {
    let trace = common::TempArtifact::new("laniusc_decimal_number", "trace", None);
    for name in ["contracts", "errors"] {
        let exe = fixture(name);
        let output = run(Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,open,openat,read,write"])
            .arg(exe.path()));
        check(&output);
        assert!(output.stdout.is_empty());
        assert!(
            std::fs::read_to_string(trace.path()).unwrap().is_empty(),
            "pure decimal operations must not allocate or perform I/O"
        );
    }
}

// Test-only reference: Fraction/Decimal for moderate exponents, arbitrary Python
// integers plus modular exponentiation for huge exponents. This does not use
// the production virtual exponent or decimal long-remainder algorithms.
const REFERENCE: &str = r#"
import sys,re
from decimal import Decimal
from fractions import Fraction
sys.set_int_max_str_digits(0)
grammar=re.compile(r'(-?)(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?\Z')
def parts(s):
 m=grammar.fullmatch(s); assert m,s
 fraction=m[3] or ''
 coefficient=int(m[2]+fraction)
 return coefficient,int(m[4] or '0')-len(fraction),bool(m[1])
def integer(c,e):
 if c==0 or e>=0:return True
 if -e>=len(str(c)):return False
 return c%10**(-e)==0
def compare(a,b):
 ca,ea,na=a;cb,eb,nb=b
 if ca==0 and cb==0:return 0
 if ca==0:return 1 if nb else -1
 if cb==0:return -1 if na else 1
 if na!=nb:return -1 if na else 1
 da=str(ca);db=str(cb);oa=len(da)+ea;ob=len(db)+eb
 if oa!=ob: order=(oa>ob)-(oa<ob)
 else:
  n=max(len(da),len(db));aa=da.ljust(n,'0');bb=db.ljust(n,'0');order=(aa>bb)-(aa<bb)
 return -order if na else order
def multiple(a,b):
 ca,ea,_=a;cb,eb,_=b
 if cb==0:return -2
 if ca==0:return 1
 delta=ea-eb
 if delta<0:
  if -delta>len(str(ca)):return 0
  return int(ca%(cb*10**(-delta))==0)
 return int((ca%cb)*pow(10,delta,cb)%cb==0)
for line in sys.stdin:
 sa,sb=line.rstrip('\n').split('\t');a=parts(sa);b=parts(sb)
 order=compare(a,b);mult=multiple(a,b)
 if abs(a[1])<=200 and abs(b[1])<=200 and len(sa)<512 and len(sb)<512:
  fa=Fraction(Decimal(sa));fb=Fraction(Decimal(sb))
  assert order==(fa>fb)-(fa<fb),(sa,sb)
  assert integer(a[0],a[1])==(fa.denominator==1)
  assert integer(b[0],b[1])==(fb.denominator==1)
  assert mult==(-2 if not fb else int((fa/fb).denominator==1)),(sa,sb)
 print(int(a[0]==0),int(a[2]),int(integer(a[0],a[1])),int(b[0]==0),int(b[2]),int(integer(b[0],b[1])),order,int(order==0),mult)
"#;

struct Generator(u64);
impl Generator {
    fn next(&mut self) -> u64 {
        self.0 = self
            .0
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        self.0 >> 24
    }
    fn number(&mut self) -> String {
        let negative = self.next() % 2 == 0;
        let mut digits = String::new();
        let n = 1 + (self.next() % 120) as usize;
        for i in 0..n {
            digits.push(char::from(
                b'0' + if i == 0 {
                    1 + (self.next() % 9) as u8
                } else {
                    (self.next() % 10) as u8
                },
            ));
        }
        if self.next() % 7 == 0 {
            digits = "0".repeat(1 + (self.next() % 20) as usize);
        }
        if self.next() % 3 == 0 {
            digits.push_str(&"0".repeat((self.next() % 20) as usize));
        }
        let fraction = (self.next() % (digits.len() as u64 + 1)) as usize;
        let split = digits.len() - fraction;
        let mut token = if fraction == 0 {
            digits.clone()
        } else if split == 0 {
            format!("0.{digits}")
        } else {
            format!("{}.{}", &digits[..split], &digits[split..])
        };
        // Zero generation above must not introduce forbidden integer zeros.
        if token.bytes().all(|v| v == b'0') {
            token = "0".to_owned();
        } else if token.starts_with("00") {
            let dot = token.find('.');
            token = match dot {
                Some(dot) => format!("0{}", &token[dot..]),
                None => "0".to_owned(),
            };
        }
        if negative {
            token.insert(0, '-');
        }
        if self.next() % 4 != 0 {
            let e = (self.next() % 201) as i32 - 100;
            token.push_str(&format!("e{e:+}"));
        }
        token
    }
}
fn cases() -> Vec<(String, String)> {
    let mut out = Vec::new();
    let selected = [
        "0",
        "-0",
        "0.0",
        "-0e-999",
        "1",
        "-1",
        "1.00",
        "0.01",
        "100e-2",
        "1e-2",
        "0.3",
        "0.1",
        "0.2",
        "128",
        "5e-10",
        "9007199254740993",
        "9007199254740992",
        "18446744073709551616",
        "1e999999999999999999",
        "1e1000000000000000000",
        "1e-999999999999999999",
        "1e-1000000000000000000",
    ];
    for a in selected {
        for b in selected {
            out.push((a.into(), b.into()));
        }
    }
    let mut generator = Generator(0x394a_725e_d54f_98b1);
    for _ in 0..900 {
        out.push((generator.number(), generator.number()));
    }
    for _ in 0..500 {
        let b = 1 + generator.next() % 1_000_000_000;
        let factor = 1 + generator.next() % 1_000_000;
        let e = (generator.next() % 121) as i32 - 60;
        let sign = if generator.next() % 2 == 0 { "-" } else { "" };
        let shift = (generator.next() % 21) as i32 - 10;
        out.push((
            format!("{sign}{}e{e}", b * factor),
            format!("{b}e{}", e + shift),
        ));
        out.push((format!("{sign}{}e{e}", b * factor + 1), format!("-{b}e{e}")));
    }
    // Shared long prefixes, exact order equality, adjacency, and carry/borrow
    // across both the 18-digit tail split and arbitrary-length exponent runs.
    for n in [18, 19, 20, 35, 36, 50, 100, 511, 1024, 4096, 8192] {
        let nines = "9".repeat(n);
        let power = format!("1{}", "0".repeat(n));
        let adjacent = format!("{}8", "9".repeat(n - 1));
        for (a, b) in [
            (format!("10e{nines}"), format!("1e{power}")),
            (format!("0.1e-{nines}"), format!("1e-{power}")),
            (format!("1e{nines}"), format!("1e{adjacent}")),
            (format!("1e-{nines}"), format!("1e-{adjacent}")),
            (format!("1e{nines}"), "128".into()),
            (format!("1e{nines}"), "3".into()),
            (format!("125e-{nines}"), format!("5e-{nines}")),
            (format!("100e{adjacent}"), format!("4e{nines}")),
            (format!("-0e-{power}"), format!("0e{power}")),
        ] {
            out.push((a, b));
        }
    }
    for n in [32, 127, 512, 2048, 8192] {
        let a = format!("{}3", "9".repeat(n - 1));
        let b = format!("{}2", "9".repeat(n - 1));
        out.push((a.clone(), b));
        out.push((a.clone(), "1".into()));
        out.push((format!("0.{a}"), format!("{a}e-{n}")));
        out.push((format!("{a}00e-2"), a));
    }
    for n in [1, 2, 17, 18, 19, 37, 100, 1000] {
        out.push((format!("1e+{}1", "0".repeat(n)), "10".into()));
        out.push((format!("10e-{}1", "0".repeat(n)), "1".into()));
    }
    // v2(2^1000)=1000 > 3*302 decimal digits. These distinguish the proved
    // 4*d bound from an insufficient 3*d cap and exercise mixed odd factors.
    let mut power = vec![1u8];
    for _ in 0..1000 {
        let mut carry = 0;
        for digit in &mut power {
            let value = *digit * 2 + carry;
            *digit = value % 10;
            carry = value / 10;
        }
        if carry != 0 {
            power.push(carry);
        }
    }
    let divisor = power
        .iter()
        .rev()
        .map(|v| char::from(b'0' + v))
        .collect::<String>();
    for exponent in [
        "999",
        "1000",
        "1001",
        "999999999999999999999999999999999999",
    ] {
        out.push((format!("1e{exponent}"), divisor.clone()));
    }
    let mut carry = 0;
    for digit in &mut power {
        let value = *digit * 3 + carry;
        *digit = value % 10;
        carry = value / 10;
    }
    if carry != 0 {
        power.push(carry);
    }
    let mixed = power
        .iter()
        .rev()
        .map(|v| char::from(b'0' + v))
        .collect::<String>();
    out.push((
        "3e999999999999999999999999999999999999".into(),
        mixed.clone(),
    ));
    out.push(("1e999999999999999999999999999999999999".into(), mixed));
    out
}

#[test]
fn decimals_match_independent_fraction_and_integer_models_including_unbounded_exponents() {
    let exe = fixture("model");
    let cases = cases();
    let input = common::TempArtifact::new("laniusc_decimal_number", "reference_input", None);
    let text = cases
        .iter()
        .map(|(a, b)| format!("{a}\t{b}\n"))
        .collect::<String>();
    input.write_bytes(text.as_bytes());
    let reference = run(Command::new("python3")
        .args(["-c", REFERENCE])
        .stdin(std::fs::File::open(input.path()).unwrap()));
    check(&reference);
    let expected = integers(&reference.stdout);
    assert_eq!(expected.len(), 9 * cases.len());
    for (chunk_index, chunk) in cases.chunks(48).enumerate() {
        let mut command = Command::new(exe.path());
        for (a, b) in chunk {
            command.arg(a).arg(b);
        }
        let output = run(&mut command);
        check(&output);
        let actual = integers(&output.stdout);
        assert_eq!(actual.len(), 9 * chunk.len());
        for (index, (a, b)) in chunk.iter().enumerate() {
            let global = chunk_index * 48 + index;
            assert_eq!(
                &actual[index * 9..index * 9 + 9],
                &expected[global * 9..global * 9 + 9],
                "case {global}: {a:?} / {b:?}"
            );
        }
    }
    let trace = common::TempArtifact::new("laniusc_decimal_number", "model_trace", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"])
        .arg(exe.path())
        .args([
            "123456789123456789123456789e9999999999999999999999999999",
            "125",
        ]));
    check(&output);
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}
