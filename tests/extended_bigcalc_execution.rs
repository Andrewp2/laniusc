#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::{ffi::OsStrExt, fs::PermissionsExt},
    process::{Command, Output, Stdio},
    sync::OnceLock,
    time::{Duration, Instant},
};

fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/bigcalc.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("bigcalc", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("bigcalc: {error}"));
        let exe = common::TempArtifact::new("laniusc_bigcalc", "executable", None);
        exe.write_bytes(&bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("bigcalc", command, Duration::from_secs(20))
}
fn file(input: &[u8]) -> common::TempArtifact {
    let data = common::TempArtifact::new("laniusc_bigcalc", "input", None);
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
fn failure(output: &Output, status: i32, message: &str, prefix: &[u8]) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert_eq!(output.stdout, prefix, "{output:?}");
    let diagnostic = std::str::from_utf8(&output.stderr).unwrap();
    assert!(
        diagnostic.starts_with("bigcalc: ")
            && diagnostic.ends_with('\n')
            && diagnostic.contains(message),
        "{output:?}"
    );
}

// Independent host reference only in the test driver. Production is entirely Lanius.
const ORACLE: &str = r#"
import sys,math
sys.set_int_max_str_digits(1000000)
radix=int(sys.argv[1]); alphabet='0123456789abcdefghijklmnopqrstuvwxyz'
def fmt(n):
    if n==0: return '0'
    negative=n<0; n=abs(n); out=''
    while n:
        n,r=divmod(n,radix); out=alphabet[r]+out
    return ('-' if negative else '')+out
for line in open(sys.argv[2],encoding='ascii'):
    words=line.split()
    if not words: continue
    op=words[0]; a=int(words[1],radix); b=int(words[2],radix) if len(words)>2 else 0
    if op in ('div','rem','divmod'):
        q=abs(a)//abs(b)
        if (a<0)!=(b<0): q=-q
        r=a-q*b
        result=(q,r) if op=='divmod' else (q if op=='div' else r,)
    elif op in ('ediv','erem','edivmod'):
        r=a%abs(b); q=(a-r)//b
        result=(q,r) if op=='edivmod' else (q if op=='ediv' else r,)
    else:
        result=({'add':lambda:a+b,'sub':lambda:a-b,'mul':lambda:a*b,
                 'cmp':lambda:(a>b)-(a<b),'shl':lambda:a<<b,'shr':lambda:a>>b,
                 'and':lambda:a&b,'or':lambda:a|b,'xor':lambda:a^b,
                 'abs':lambda:abs(a),'neg':lambda:-a,'not':lambda:~a,
                 'gcd':lambda:math.gcd(a,b),'pow':lambda:pow(a,b)}[op](),)
    print(' '.join(fmt(n) for n in result))
"#;
fn oracle(radix: u32, input: &[u8]) -> Vec<u8> {
    let data = file(input);
    let result = run(Command::new("python3")
        .args(["-c", ORACLE, &radix.to_string()])
        .arg(data.path()));
    assert!(
        result.status.success() && result.stderr.is_empty(),
        "{result:?}"
    );
    result.stdout
}
fn random(state: &mut u64) -> u64 {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state
}
fn numeral(state: &mut u64, radix: u32, count: usize, negative: bool) -> String {
    let alphabet = b"0123456789abcdefghijklmnopqrstuvwxyz";
    let mut out = if negative {
        "-".to_owned()
    } else {
        "+".to_owned()
    };
    out.push(alphabet[(random(state) % (radix as u64 - 1) + 1) as usize] as char);
    for _ in 1..count {
        out.push(alphabet[(random(state) % radix as u64) as usize] as char);
    }
    out
}
fn small_radix(mut n: u32, radix: u32) -> String {
    let mut out = Vec::new();
    loop {
        out.push(b"0123456789abcdefghijklmnopqrstuvwxyz"[(n % radix) as usize]);
        n /= radix;
        if n == 0 {
            break;
        }
    }
    out.reverse();
    String::from_utf8(out).unwrap()
}
#[test]
fn bigcalc_matches_seeded_python_signed_arithmetic_division_and_bits_in_supported_radices() {
    // Reproducible seed; mix operand signs and sizes to cover long carries,
    // unequal limb counts, negative quotients, and two's complement extension.
    let mut seed = 0x72b8_f041_093c_5aedu64;
    for radix in [2, 3, 10, 16, 35, 36] {
        let mut input = String::new();
        for index in 0..12 {
            let left = numeral(&mut seed, radix, 1 + index * 13, index % 2 == 0);
            let right = numeral(&mut seed, radix, 1 + index * 7, index % 3 == 0);
            for op in [
                "add", "sub", "mul", "div", "rem", "divmod", "ediv", "erem", "edivmod", "cmp",
                "and", "or", "xor", "gcd",
            ] {
                input.push_str(&format!("{op} {left} {right}\n"));
            }
            input.push_str(&format!(
                "pow {left} {}\n",
                small_radix(index as u32 % 9, radix)
            ));
            for op in ["abs", "neg", "not"] {
                input.push_str(&format!("{op} {left}\n"));
            }
            for shift in [0, 1, 31, 32, 33, 127, 255] {
                let shift = small_radix(shift, radix);
                input.push_str(&format!("shl {left} {shift}\nshr {left} {shift}\n"));
            }
        }
        input.push_str("add -0 +0\nnot -0\ncmp 0 0\npow 0 0\ngcd 0 0\ngcd -1 0\n");
        let expected = oracle(radix, input.as_bytes());
        let option = format!("--radix={radix}");
        success(&invoke(&[&option], input.as_bytes()), &expected);
    }
}
#[test]
fn bigcalc_streams_thousands_of_digits_and_reports_scale() {
    let left = format!("-{}", "9876543210".repeat(400));
    let right = "1234567890".repeat(190);
    let input = format!(
        "add {left} {right}\nsub {left} {right}\nmul {left} {right}\ndivmod {left} {right}\nedivmod {left} -{right}\n"
    );
    assert!(input.len() > 8192); // stdin operands surpass the argument snapshot budget.
    let expected = oracle(10, input.as_bytes());
    let _ = executable();
    let started = Instant::now();
    let output = invoke(&[], input.as_bytes());
    let elapsed = started.elapsed();
    success(&output, &expected);
    eprintln!(
        "bigcalc x86_64 Linux: 4000/1900 decimal digits, 5 records, {} input bytes, {} output bytes, {:?} native wall time (includes process startup)",
        input.len(),
        expected.len(),
        elapsed
    );
    // EOF can terminate the last record and CRLF/whitespace do not change values.
    success(
        &invoke(&[], b"\n\t\r\n  add\t+00012 -2\r\nneg -0"),
        b"10\n0\n",
    );
}
#[test]
fn bigcalc_distinguishes_binary_syntax_arity_limits_arithmetic_and_argument_failures() {
    for (input, message) in [
        (b"bad 1 2\n".as_slice(), "unknown-operation line=1 byte=0"),
        (b"add 1\n", "invalid-arity line=1 byte=5"),
        (b"add 1 2 3\n", "invalid-arity line=1 byte=8"),
        (b"not 1 2\n", "invalid-arity line=1 byte=6"),
        (b"add + 2\n", "invalid-operand line=1 byte=5 operand=1"),
        (b"add 1 2\0\n", "invalid-operand line=1 byte=7 operand=2"),
        (b"add 1 \xff\n", "invalid-operand line=1 byte=6 operand=2"),
        (b"add 1 0x10\n", "invalid-operand line=1 byte=7 operand=2"),
        (b"add 1 1_0\n", "invalid-operand line=1 byte=7 operand=2"),
        (b"add 1 1.0\n", "invalid-operand line=1 byte=7 operand=2"),
    ] {
        failure(&invoke(&[], input), 2, message, b"");
    }
    failure(
        &invoke(&[], b"add 1 2\n\nadd 3 \xff\nadd 4 5\n"),
        2,
        "line=3 byte=6 operand=2",
        b"3\n",
    );
    failure(
        &invoke(&["--radix=2"], b"add 1 2\n"),
        2,
        "invalid-operand",
        b"",
    );
    success(&invoke(&["-r16"], b"add FF a\n"), b"109\n");
    success(&invoke(&["--radix=36"], b"add Z 1\n"), b"10\n");
    for args in [
        vec!["--unknown"],
        vec!["--radix"],
        vec!["--radix=1"],
        vec!["--radix=37"],
        vec!["--max-line=-1"],
        vec!["--max-work=+1"],
        vec!["--max-work=18446744073709551616"],
        vec!["--max-limbs=536870912"],
        vec!["--help=yes"],
        vec!["add"],
    ] {
        failure(&invoke(&args, b""), 2, "invalid-arguments", b"");
    }
    let data = file(b"");
    let non_utf8 = run(Command::new(executable().path())
        .arg(std::ffi::OsStr::from_bytes(b"--radix=\xff"))
        .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())));
    failure(&non_utf8, 2, "invalid-arguments argument=0 byte=8", b"");
    for (options, input, status, message) in [
        (
            vec!["--max-line=6"],
            b"add 1 2\n".as_slice(),
            3,
            "line-limit line=1 byte=6",
        ),
        (vec!["--max-limbs=0"], b"add 1 0\n", 3, "limb-limit"),
        (vec!["--max-work=0"], b"add 1 1\n", 4, "work-limit"),
        (vec!["--max-output=1"], b"add 0 0\n", 3, "output-limit"),
        (vec!["--max-output=3"], b"divmod 7 2\n", 3, "output-limit"),
        (
            vec![],
            b"div 1 0\n",
            7,
            "division-by-zero line=1 byte=6 operand=2",
        ),
        (
            vec![],
            b"shl 1 -1\n",
            7,
            "invalid-shift line=1 byte=6 operand=2",
        ),
        (
            vec![],
            b"shr 1 18446744073709551616\n",
            7,
            "invalid-shift line=1 byte=6 operand=2",
        ),
    ] {
        failure(&invoke(&options, input), status, message, b"");
    }
    failure(
        &invoke(&[], b"pow 2 -1\n"),
        7,
        "invalid-exponent line=1 byte=6 operand=2",
        b"",
    );
    failure(
        &invoke(&[], b"pow 2 4294967296\n"),
        7,
        "invalid-exponent line=1 byte=6 operand=2",
        b"",
    );
    failure(
        &invoke(&[], b"pow 2 18446744073709551616\n"),
        7,
        "invalid-exponent",
        b"",
    );
    success(
        &invoke(
            &[],
            b"pow -1 4294967295\npow 0 0\npow 0 4294967295\ngcd -48 18\ngcd 0 -25\n",
        ),
        b"-1\n1\n0\n6\n25\n",
    );
    failure(
        &invoke(&["--max-limbs=1"], b"pow 2 32\n"),
        3,
        "limb-limit",
        b"",
    );
    success(
        &invoke(&["--max-line=7", "--max-output=2"], b"add 1 2\n"),
        b"3\n",
    );
    success(&invoke(&["--max-line=0"], b"\n\n"), b"");
    success(&invoke(&["--max-output=4"], b"divmod 7 2\n"), b"3 1\n");
    let help = invoke(&["--help"], b"bad\n");
    assert_eq!(help.status.code(), Some(0), "{help:?}");
    assert!(
        help.stdout.starts_with(b"Usage: bigcalc ")
            && help.stdout.ends_with(b" gcd pow\n")
            && help.stderr.is_empty(),
        "{help:?}"
    );
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
fn bigcalc_cleans_up_every_observed_allocation_denial_and_io_fault() {
    assert!(
        Command::new("strace")
            .arg("-V")
            .output()
            .unwrap()
            .status
            .success()
    );
    // Nonzero Euclidean adjustment owns the original pair, adjusted remainder,
    // increment scratch and final pair. Two formatted outputs add failure points.
    let input = b"edivmod -184467440737095516170000000000001 4294967297\n";
    let data = file(input);
    let trace = common::TempArtifact::new("laniusc_bigcalc", "trace", None);
    let expected = oracle(10, input);
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
            .args(["--radix=10", "--max-line=1048576"])
            .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())));
        assert_eq!(
            output.status.code(),
            Some(status),
            "injection={injection:?}: {output:?}"
        );
        if status == 0 {
            assert_eq!(output.stdout, expected, "{output:?}");
            assert!(output.stderr.is_empty(), "{output:?}");
        } else {
            assert!(
                expected.starts_with(&output.stdout),
                "failed write emitted an invalid prefix: {output:?}"
            );
            assert!(
                output.stderr.starts_with(b"bigcalc: ") && output.stderr.ends_with(b"\n"),
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
    assert!(allocations > 10, "{events}");
    for when in 1..=allocations {
        let (_, _, output) = execute(Some(&format!("mmap:error=ENOMEM:when={when}")), 5);
        assert!(
            output.stdout.is_empty(),
            "allocation failure must precede record output: {output:?}"
        );
    }
    let reads = events
        .lines()
        .filter(|line| line.starts_with("read("))
        .count();
    for when in 1..=reads {
        execute(Some(&format!("read:error=EIO:when={when}")), 6);
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
    // strace reports one successful byte without transferring it. write_all
    // must resume at byte 1, and the remainder must reach the descriptor once.
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
    // A descriptor that rejects output returns the I/O status after cleanup.
    let output = run(Command::new("sh")
        .args(["-c", "exec \"$1\" <\"$2\" > /dev/full", "bigcalc"])
        .arg(executable().path())
        .arg(data.path()));
    failure(&output, 6, "io-failure", b"");
    // Failed stderr is still an I/O status, and does not skip owner destruction.
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
}
