#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
    sync::OnceLock,
    time::{Duration, Instant},
};

fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/expr_calc.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("expr_calc", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("expr_calc: {error}"));
        let exe = common::TempArtifact::new("laniusc_expr_calc", "executable", None);
        exe.write_bytes(&bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("expr_calc", command, Duration::from_secs(30))
}
fn file(input: &[u8]) -> common::TempArtifact {
    let data = common::TempArtifact::new("laniusc_expr_calc", "input", None);
    data.write_bytes(input);
    data
}
fn invoke(options: &[&str], input: &[u8]) -> Output {
    let data = file(input);
    run(Command::new(executable().path())
        .args(options)
        .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())))
}
fn success(output: &Output, expected: &[u8]) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stdout, expected, "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn failure(output: &Output, status: i32, message: &str) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(
        output.stdout.is_empty(),
        "late failure must discard all staged answers: {output:?}"
    );
    let diagnostic = std::str::from_utf8(&output.stderr).unwrap();
    assert!(
        diagnostic.starts_with("expr_calc: ")
            && diagnostic.ends_with('\n')
            && diagnostic.contains(message),
        "{output:?}"
    );
}

// Independent recursive grammar and exact rational division, confined to tests.
// Production parsing uses bounded iterative stacks and has no host evaluator.
const ORACLE: &str = r#"
import sys,re
from fractions import Fraction
MIN=-(1<<63); MAX=(1<<63)-1
class Error(Exception): pass
def checked(value):
    if not MIN <= value <= MAX: raise Error('overflow')
    return value
class Parser:
    def __init__(self,line):
        self.tokens=re.findall(r'[0-9]+|[^ \t\v\f]',line); self.at=0
    def peek(self): return self.tokens[self.at] if self.at<len(self.tokens) else ''
    def take(self):
        token=self.peek(); self.at+=1; return token
    def primary(self):
        token=self.take()
        if token=='(':
            value=self.add()
            if self.take()!=')': raise Error('syntax')
            return value
        if not token or not token.isascii() or not token.isdigit(): raise Error('syntax')
        return checked(int(token))
    def unary(self):
        token=self.peek()
        if token in ('+','-'):
            self.take()
            # Decimal magnitude 2^63 is allowed directly under unary minus.
            if token=='-' and self.peek().isascii() and self.peek().isdigit():
                return checked(-int(self.take()))
            value=self.unary()
            return checked(-value if token=='-' else value)
        return self.primary()
    def mul(self):
        value=self.unary()
        while self.peek() in ('*','/','%'):
            op=self.take(); right=self.unary()
            if op=='*': value=checked(value*right)
            else:
                if not right: raise Error('division-by-zero')
                if value==MIN and right==-1: raise Error('overflow')
                quotient=int(Fraction(value,right))
                value=checked(quotient if op=='/' else value-quotient*right)
        return value
    def add(self):
        value=self.mul()
        while self.peek() in ('+','-'):
            op=self.take(); right=self.mul()
            value=checked(value+right if op=='+' else value-right)
        return value
for line in open(sys.argv[1],encoding='utf-8'):
    try:
        parser=Parser(line.rstrip('\n')); value=parser.add()
        if parser.peek(): raise Error('syntax')
        print('OK',value)
    except Error as error: print('ERR',error)
"#;
fn oracle(input: &[u8]) -> Vec<String> {
    let data = file(input);
    let result = run(Command::new("python3")
        .args(["-c", ORACLE])
        .arg(data.path()));
    assert!(
        result.status.success() && result.stderr.is_empty(),
        "{result:?}"
    );
    String::from_utf8(result.stdout)
        .unwrap()
        .lines()
        .map(str::to_owned)
        .collect()
}
fn random(seed: &mut u64) -> u64 {
    *seed ^= *seed << 13;
    *seed ^= *seed >> 7;
    *seed ^= *seed << 17;
    *seed
}
fn expression(seed: &mut u64, depth: u32) -> String {
    if depth == 0 || random(seed) % 5 == 0 {
        return match random(seed) % 12 {
            0 => "9223372036854775807".into(),
            1 => "-9223372036854775808".into(),
            2 => "0".into(),
            _ => (random(seed) % 2001).to_string(),
        };
    }
    if random(seed) % 5 == 0 {
        let sign = if random(seed) & 1 == 0 { '+' } else { '-' };
        return format!("{sign} ({})", expression(seed, depth - 1));
    }
    let left = expression(seed, depth - 1);
    let right = expression(seed, depth - 1);
    let op = b"+-*/%"[(random(seed) % 5) as usize] as char;
    format!("({left}\t{op} {right})")
}
#[test]
fn expr_calc_matches_independent_checked_python_fraction_model() {
    let mut cases = vec![
        "1+2*3",
        "(1+2)*3",
        "20/3*3",
        "20/(3*3)",
        "10-3-2",
        "10-(3-2)",
        "-7/3",
        "7/-3",
        "-7%-3",
        "7%-3",
        "--2",
        "-+-2",
        "+-2",
        "-(+2)*-3",
        "-9223372036854775808",
        "- 9223372036854775808",
        "+-9223372036854775808",
        "0*-9223372036854775808",
        "9223372036854775807+1",
        "-9223372036854775808-1",
        "-(-9223372036854775808)",
        "--9223372036854775808",
        "-+9223372036854775808",
        "9223372036854775808",
        "+9223372036854775808",
        "-9223372036854775808/-1",
        "-9223372036854775808%-1",
        "3037000500*3037000500",
        "-9223372036854775808*1",
        "-9223372036854775808*0",
        "-9223372036854775808*-1",
        "1/(2-2)",
        "1%0",
        "0000012 +\t34",
        "-(1+2) * +(+3)",
    ]
    .into_iter()
    .map(str::to_owned)
    .collect::<Vec<_>>();
    let mut seed = 0x7d91_24a8_c56f_031bu64;
    for _ in 0..320 {
        cases.push(expression(&mut seed, 4));
    }
    let input = cases.join("\n") + "\n";
    let expected = oracle(input.as_bytes());
    assert_eq!(expected.len(), cases.len());
    let mut good_input = String::new();
    let mut good_output = String::new();
    let mut failures = 0;
    for (case, answer) in cases.iter().zip(expected) {
        if let Some(value) = answer.strip_prefix("OK ") {
            good_input.push_str(case);
            good_input.push('\n');
            good_output.push_str(value);
            good_output.push('\n');
        } else {
            failures += 1;
            let reason = answer.strip_prefix("ERR ").unwrap();
            failure(
                &invoke(&[], format!("2+3\n{case}\n8*9\n").as_bytes()),
                7,
                reason,
            );
        }
    }
    assert!(failures > 50 && good_input.lines().count() > 100);
    success(&invoke(&[], good_input.as_bytes()), good_output.as_bytes());
}
#[test]
fn expr_calc_rejects_malformed_records_with_original_byte_positions_and_no_partial_batch() {
    for (input, message) in [
        (b"1+\n".as_slice(), "syntax line=1 byte=2"),
        (b"1 2\n", "syntax line=1 byte=2"),
        (b"2(3)\n", "syntax line=1 byte=1"),
        (b"()\n", "syntax line=1 byte=1"),
        (b"(1+2\n", "parenthesis line=1 byte=0"),
        (b"1+2)\n", "parenthesis line=1 byte=3"),
        (b"*1\n", "syntax line=1 byte=0"),
        (b"1**2\n", "syntax line=1 byte=2"),
        (b"1^2\n", "syntax line=1 byte=1"),
        (b"1.0\n", "syntax line=1 byte=1"),
        (b"0x10\n", "syntax line=1 byte=1"),
        (b"1_000\n", "syntax line=1 byte=1"),
        (b"ABS(1)\n", "syntax line=1 byte=0"),
        (b"1\0+2\n", "syntax line=1 byte=1"),
        (b"1+\xff\n", "invalid-utf8 line=1 byte=2"),
        (b"1+\xe2\x82\n", "invalid-utf8 line=1 byte=2"),
        ("1+é\n".as_bytes(), "syntax line=1 byte=2"),
        ("\u{2003}1\n".as_bytes(), "syntax line=1 byte=0"),
        (b"1\r+2\n", "syntax line=1 byte=1"),
        (b"1\r", "syntax line=1 byte=1"),
    ] {
        failure(&invoke(&[], input), 2, message);
    }
    failure(
        &invoke(&[], b"1+2\n\r\n4/0\n7*8\n"),
        7,
        "division-by-zero line=3 byte=1",
    );
    failure(
        &invoke(&[], b"1+2\n4+\xff\n"),
        2,
        "invalid-utf8 line=2 byte=2",
    );
    success(
        &invoke(&[], b"\n\t\r\n \x0b\x0c\t1+2\r\n-(3 + 4)"),
        b"3\n-7\n",
    );
    success(&invoke(&[], b""), b"");
}
#[test]
fn expr_calc_enforces_every_capacity_and_option_boundary() {
    success(
        &invoke(
            &[
                "--max-input=4",
                "--max-line=3",
                "--max-output=2",
                "--max-stack=2",
            ],
            b"1+2\n",
        ),
        b"3\n",
    );
    for (options, input, status, reason) in [
        (vec!["--max-input=3"], b"1+2\n".as_slice(), 3, "input-limit"),
        (vec!["--max-line=2"], b"1+2\n", 3, "line-limit"),
        (vec!["--max-output=3"], b"1\n2\n", 3, "output-limit"),
        (vec!["--max-stack=1"], b"1+2\n", 3, "stack-limit"),
        (vec!["--max-stack=1"], b"((1))\n", 3, "stack-limit"),
        (vec!["--max-stack=0"], b"1\n", 3, "stack-limit"),
        (vec!["--max-work=0"], b"1\n", 4, "work-limit"),
        (vec!["--max-work=2"], b"1+2\n", 4, "work-limit"),
        (vec!["--max-output=0"], b"1\n", 3, "output-limit"),
        (vec!["--max-line=0"], b"1\n", 3, "line-limit"),
    ] {
        failure(&invoke(&options, input), status, reason);
    }
    success(
        &invoke(
            &[
                "--max-input=0",
                "--max-output=0",
                "--max-stack=0",
                "--max-work=0",
            ],
            b"",
        ),
        b"",
    );
    success(&invoke(&["--max-line=0"], b"\n\n"), b"");
    success(
        &invoke(&["--max-work=18446744073709551615"], b"1+2\n"),
        b"3\n",
    );
    success(
        &invoke(&["--max-output=0", "--max-output", "2"], b"1\n"),
        b"1\n",
    );
    for option in [
        "--unknown",
        "--max-input=-1",
        "--max-line=2147483648",
        "--max-stack=257",
        "--max-work=+1",
        "--max-work=18446744073709551616",
        "--max-output",
        "--help=yes",
        "1+2",
    ] {
        failure(&invoke(&[option], b"1+2\n"), 2, "invalid-arguments");
    }
    let too_many = vec!["--help"; 33];
    failure(&invoke(&too_many, b""), 2, "invalid-arguments");
    let too_long = format!("--max-work={}", "0".repeat(8192));
    failure(&invoke(&[&too_long], b""), 2, "invalid-arguments");
    let help = invoke(&["--help"], b"broken\xff");
    assert_eq!(help.status.code(), Some(0), "{help:?}");
    assert!(
        help.stdout.starts_with(b"Usage: expr_calc ")
            && help.stdout.ends_with(b"unary + -.\n")
            && help.stderr.is_empty(),
        "{help:?}"
    );
    let deep = format!("{}1{}\n", "(".repeat(256), ")".repeat(256));
    success(&invoke(&[], deep.as_bytes()), b"1\n");
    let too_deep = format!("{}1{}\n", "(".repeat(257), ")".repeat(257));
    failure(&invoke(&[], too_deep.as_bytes()), 3, "stack-limit");
    let unary = format!("{}1\n", "+".repeat(257));
    failure(&invoke(&[], unary.as_bytes()), 3, "stack-limit");
}
#[test]
fn expr_calc_runs_a_large_mixed_batch_and_reports_native_time_excluding_compilation() {
    let patterns = [
        "1+2*3-4/2",
        "-(100-7)*3%11",
        "-9223372036854775808/17",
        "(1000+25)*(1000-25)",
        "--17 + -(-3*8)",
        "3000000000*3000000000",
        "-7%3+7/-3",
    ];
    let mut input = String::new();
    for index in 0..5000 {
        input.push_str(patterns[index % patterns.len()]);
        input.push_str(if index % 3 == 0 { "\r\n" } else { "\n" });
    }
    let normalized = input.replace("\r\n", "\n");
    let expected = oracle(normalized.as_bytes())
        .into_iter()
        .map(|line| format!("{}\n", line.strip_prefix("OK ").expect("valid batch")))
        .collect::<String>();
    let _ = executable();
    let started = Instant::now();
    let output = invoke(&[], input.as_bytes());
    let elapsed = started.elapsed();
    success(&output, expected.as_bytes());
    eprintln!("expr_calc x86_64 Linux: 5000 mixed expressions, {} input bytes, {} output bytes, {:?} native wall time including process startup; compilation excluded", input.len(), expected.len(), elapsed);
}
fn no_leaks(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut allocations = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(
                    live.insert(result.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                allocations += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "unreleased allocations: {events}");
    allocations
}
#[test]
fn expr_calc_releases_owners_at_each_allocation_failure_and_io_fault() {
    let input = format!(
        "{}1{}\n{}",
        "(".repeat(40),
        ")".repeat(40),
        "-17*3+9\n".repeat(400)
    );
    let data = file(input.as_bytes());
    let expected = format!("1\n{}", "-42\n".repeat(400)).into_bytes();
    let trace = common::TempArtifact::new("laniusc_expr_calc", "trace", None);
    let execute = |injection: Option<&str>, status: i32| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write"]);
        if let Some(fault) = injection {
            command.arg("-e").arg(format!("inject={fault}"));
        }
        let output = run(command
            .arg(executable().path())
            .arg("--max-input=1048576")
            .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())));
        assert_eq!(
            output.status.code(),
            Some(status),
            "injection={injection:?}: {output:?}"
        );
        if status == 0 {
            success(&output, &expected);
        } else {
            assert!(expected.starts_with(&output.stdout), "{output:?}");
            assert!(
                output.stderr.starts_with(b"expr_calc: ") && output.stderr.ends_with(b"\n"),
                "{output:?}"
            );
        }
        let events = std::fs::read_to_string(trace.path()).unwrap();
        let allocations = no_leaks(&events);
        if injection.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        (allocations, events, output)
    };
    let (allocations, events, _) = execute(None, 0);
    assert!(allocations > 8, "{events}");
    for when in 1..=allocations {
        let (_, _, output) = execute(Some(&format!("mmap:error=ENOMEM:when={when}")), 5);
        assert!(
            output.stdout.is_empty(),
            "allocation failure must precede all output: {output:?}"
        );
    }
    let reads = events
        .lines()
        .filter(|line| line.starts_with("read("))
        .count();
    for when in 1..=reads {
        let (_, _, output) = execute(Some(&format!("read:error=EIO:when={when}")), 6);
        assert!(output.stdout.is_empty());
    }
    execute(Some("read:error=EINTR:when=1"), 0);
    execute(Some("read:error=EAGAIN:when=1"), 6);
    let writes = events
        .lines()
        .filter(|line| line.starts_with("write("))
        .count();
    for when in 1..=writes {
        execute(Some(&format!("write:error=EIO:when={when}")), 6);
        execute(Some(&format!("write:retval=0:when={when}")), 6);
        execute(Some(&format!("write:error=EINTR:when={when}")), 0);
    }
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap,write",
            "-e",
            "inject=write:retval=1:when=1",
        ])
        .arg(executable().path())
        .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())));
    success(&output, &expected[1..]);
    no_leaks(&std::fs::read_to_string(trace.path()).unwrap());
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap,write",
            "-e",
            "inject=write:error=EIO:when=1",
        ])
        .arg(executable().path())
        .arg("--unknown"));
    assert_eq!(output.status.code(), Some(6), "{output:?}");
    no_leaks(&std::fs::read_to_string(trace.path()).unwrap());
    let bad = file(b"1+2\n1/0\n");
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"])
        .arg(executable().path())
        .stdin(Stdio::from(std::fs::File::open(bad.path()).unwrap())));
    failure(&output, 7, "division-by-zero line=2 byte=1");
    no_leaks(&std::fs::read_to_string(trace.path()).unwrap());
}
