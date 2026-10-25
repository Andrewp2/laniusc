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
        let entry = root.join("sample_programs/library/decimal_ledger.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("decimal ledger", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("decimal ledger: {error}"));
        let exe = common::TempArtifact::new("laniusc_decimal_ledger", "executable", None);
        exe.write_bytes(&bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("decimal ledger", command, Duration::from_secs(25))
}
fn file(input: &[u8]) -> common::TempArtifact {
    let data = common::TempArtifact::new("laniusc_decimal_ledger", "input", None);
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
        "failed validation must publish no report: {output:?}"
    );
    let diagnostic = std::str::from_utf8(&output.stderr).unwrap();
    assert!(
        diagnostic.starts_with("decimal_ledger: ")
            && diagnostic.ends_with('\n')
            && diagnostic.contains(message),
        "{output:?}"
    );
}

// Independent decimal arithmetic exists only in the test driver. The program
// parses, calculates, rounds, encodes and writes entirely through Lanius.
const ORACLE: &str = r#"
import csv,decimal,io,sys
scale=int(sys.argv[1]); mode=sys.argv[2]; header=sys.argv[3]=='1'
rounding={'down':decimal.ROUND_DOWN,'up':decimal.ROUND_UP,'floor':decimal.ROUND_FLOOR,
          'ceiling':decimal.ROUND_CEILING,'half-up':decimal.ROUND_HALF_UP,
          'half-down':decimal.ROUND_HALF_DOWN,'half-even':decimal.ROUND_HALF_EVEN,
          'unnecessary':decimal.ROUND_DOWN}[mode]
rows=csv.reader(open(sys.argv[4],encoding='utf8',newline=''),strict=True)
if header: assert next(rows)==['label','quantity','unit_price','tax_rate']
out=io.StringIO(newline=''); writer=csv.writer(out,quoting=csv.QUOTE_ALL,lineterminator='\r\n')
sys.stdout.write('kind,label,quantity,unit_price,tax_rate,subtotal,tax,total,running_total\r\n')
with decimal.localcontext() as ctx:
    ctx.prec=50000; ctx.rounding=rounding; ctx.traps[decimal.Inexact]=(mode=='unnecessary')
    unit=decimal.Decimal((0,(1,),-scale)); running=decimal.Decimal(0).quantize(unit)
    def fmt(value): return format(value.copy_abs() if value.is_zero() else value,'f')
    for label,q,p,r in rows:
        subtotal=(decimal.Decimal(q)*decimal.Decimal(p)).quantize(unit)
        tax=(subtotal*decimal.Decimal(r)).quantize(unit)
        total=subtotal+tax; running+=total
        writer.writerow(['line',label,q,p,r,fmt(subtotal),fmt(tax),fmt(total),fmt(running)])
    writer.writerow(['total','','','','','','','',fmt(running)])
sys.stdout.write(out.getvalue())
"#;
fn oracle(scale: u32, mode: &str, header: bool, input: &[u8]) -> Vec<u8> {
    let data = file(input);
    let output = run(Command::new("python3")
        .args([
            "-c",
            ORACLE,
            &scale.to_string(),
            mode,
            if header { "1" } else { "0" },
        ])
        .arg(data.path()));
    assert!(
        output.status.success() && output.stderr.is_empty(),
        "{output:?}"
    );
    output.stdout
}
fn quoted(value: &str) -> String {
    format!("\"{}\"", value.replace('"', "\"\""))
}
fn seeded_rows(count: usize) -> Vec<u8> {
    let mut seed = 0x8bd5_172c_64a0_21efu64;
    let mut input = String::from("label,quantity,unit_price,tax_rate\r\n");
    let labels = [
        "",
        "refund",
        "é🙂",
        "comma,label",
        "quoted\"label",
        "multi\r\nline",
        " spaced ",
    ];
    for row in 0..count {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        let quantity = format!(
            "{}{}.{:02}",
            if row % 3 == 0 { "-" } else { "+" },
            seed % 1000,
            (seed >> 20) % 100
        );
        let price = format!("{}.{:03}", (seed >> 8) % 100000, (seed >> 28) % 1000);
        let rate = match row % 5 {
            0 => "0.0825",
            1 => "0",
            2 => "0.125",
            3 => "0.05",
            _ => "0.333",
        };
        input.push_str(&format!(
            "{},{quantity},{price},{rate}{}",
            quoted(labels[row % labels.len()]),
            if row % 2 == 0 { "\n" } else { "\r\n" }
        ));
    }
    input.into_bytes()
}
#[test]
fn ledger_matches_decimal_oracle_for_rounding_ties_refunds_labels_and_large_coefficients() {
    let input=b"label,quantity,unit_price,tax_rate\nregular,+0002.50,1.0050,0.1250\nrefund,-2.5,1.005,0.125\npositive,1,1.005,0\nnegative,-1,1.005,0\neven,1,1.015,0\nnegative-even,-1,1.015,0\nzero,-0.00,9.50,0.20\n\"comma,quote\"\"\xc3\xa9\",3e1,2.00E-1,0.075\n";
    for mode in [
        "down",
        "up",
        "floor",
        "ceiling",
        "half-up",
        "half-down",
        "half-even",
    ] {
        let option = format!("--round={mode}");
        success(
            &invoke(&["--header", &option], input),
            &oracle(2, mode, true, input),
        );
    }
    let exact = b"exact,1.2500,2.00,0.20\nrefund,-2,10.00,0.10";
    success(
        &invoke(&["--round=unnecessary"], exact),
        &oracle(2, "unnecessary", false, exact),
    );
    failure(
        &invoke(&["--round=unnecessary"], b"tie,1,1.005,0\n"),
        2,
        "rounding-required",
    );
    for scale in [0, 1, 6] {
        let option = format!("--scale={scale}");
        success(
            &invoke(&["--header", &option], input),
            &oracle(scale, "half-even", true, input),
        );
    }
    let huge = format!(
        "huge,{}.005,{}.25,0.0825\nrefund,-{}.005,{}.25,0.0825\n",
        "9876543210".repeat(120),
        "1234567890".repeat(60),
        "9876543210".repeat(120),
        "1234567890".repeat(60)
    );
    success(
        &invoke(&[], huge.as_bytes()),
        &oracle(2, "half-even", false, huge.as_bytes()),
    );
    success(&invoke(&[], b""), &oracle(2, "half-even", false, b""));
    success(
        &invoke(&["--header"], b"label,quantity,unit_price,tax_rate\n"),
        &oracle(
            2,
            "half-even",
            true,
            b"label,quantity,unit_price,tax_rate\n",
        ),
    );
}
#[test]
fn ledger_stages_all_rows_and_checks_syntax_options_and_resource_boundaries() {
    let valid = b"label,quantity,unit_price,tax_rate\nfirst,2,1.25,0.20\n";
    for bad in [
        "bad,1,,0\n",
        "bad,1, 2,0\n",
        "bad,1,1_0,0\n",
        "bad,1,0x10,0\n",
        "bad,1,1e,0\n",
        "bad,1,.,0\n",
        "bad,1,NaN,0\n",
        "bad,1,Infinity,0\n",
        "bad,1,-inf,0\n",
        "bad,1,2\n",
        "\"unfinished,1,2,0",
        "bad\"quote,1,2,0\n",
        "bad,1,2,0\r",
    ] {
        let mut input = valid.to_vec();
        input.extend_from_slice(bad.as_bytes());
        let output = invoke(&["--header"], &input);
        assert_eq!(output.status.code(), Some(2), "{bad:?}: {output:?}");
        assert!(output.stdout.is_empty(), "{bad:?}: {output:?}");
        assert!(!output.stderr.is_empty(), "{output:?}");
    }
    for bad in [
        b"bad\xff,1,2,0\n".as_slice(),
        b"bad\0,1,2,0\n",
        b"bad,1,2,0\n\xc3",
    ] {
        let mut input = valid.to_vec();
        input.extend_from_slice(bad);
        failure(&invoke(&["--header"], &input), 2, "invalid-csv");
    }
    // CSV offsets refer to raw bytes, including the already validated prefix.
    for (bad, offset) in [
        (b"bad\xff,1,2,0\n".as_slice(), 3),
        (b"\"unfinished,1,2,0".as_slice(), 0),
        (b"bad,1,2,0\r".as_slice(), 9),
    ] {
        let mut input = valid.to_vec();
        input.extend_from_slice(bad);
        let output = invoke(&["--header"], &input);
        failure(&output, 2, "invalid-csv");
        assert_eq!(
            output.stderr,
            format!(
                "decimal_ledger: invalid-csv record=3 byte={}\n",
                valid.len() + offset
            )
            .as_bytes()
        );
    }
    failure(
        &invoke(&["--header"], b""),
        2,
        "expected-four-column-record",
    );
    failure(
        &invoke(&["--header"], b"wrong,quantity,unit_price,tax_rate\n"),
        2,
        "expected-four-column-record",
    );
    failure(&invoke(&[], b"\n"), 2, "expected-four-column-record");
    for options in [
        vec!["--unknown"],
        vec!["--scale"],
        vec!["--scale=-1"],
        vec!["--scale=3", "--max-scale=2"],
        vec!["--round=bankers"],
        vec!["--max-input=+1"],
        vec!["--max-work=18446744073709551616"],
        vec!["--max-field=536870912"],
        vec!["--max-digits=0"],
        vec!["--max-scale=1000000001"],
        vec!["--header=yes"],
        vec!["--help=yes"],
        vec!["operand"],
    ] {
        failure(&invoke(&options, b""), 2, "invalid-arguments");
    }
    // A cross-option relationship must not blame an unrelated later value.
    let crossed = invoke(&["--scale=3", "--max-scale=2", "--round=half-even"], b"");
    failure(&crossed, 2, "invalid-arguments");
    assert_eq!(crossed.stderr, b"decimal_ledger: invalid-arguments\n");
    let limited = invoke(&["--max-field=3"], b"a,2,1.25,0.20\n");
    failure(&limited, 3, "input-limit");
    assert_eq!(
        limited.stderr,
        b"decimal_ledger: input-limit record=1 byte=7\n"
    );
    let input = file(b"");
    let raw = run(Command::new(executable().path())
        .arg(std::ffi::OsStr::from_bytes(b"--round=\xff"))
        .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
    failure(&raw, 2, "invalid-arguments");
    failure(&invoke(&[], b"a,1,2,0,extra\n"), 3, "input-limit");
    let row = b"a,2,1.25,0.20\n";
    let expected = oracle(2, "half-even", false, row);
    let exact_output = format!("--max-output={}", expected.len());
    let short_output = format!("--max-output={}", expected.len() - 1);
    success(
        &invoke(
            &[
                &exact_output,
                "--max-rows=1",
                "--max-field=4",
                "--max-input=14",
            ],
            row,
        ),
        &expected,
    );
    for (options, status, message) in [
        (vec!["--max-rows=0"], 3, "input-limit"),
        (vec!["--max-field=3"], 3, "input-limit"),
        (vec!["--max-input=13"], 3, "input-limit"),
        (vec!["--max-limbs=0"], 3, "decimal-limit"),
        (vec!["--max-digits=2"], 3, "decimal-limit"),
        (vec!["--max-work=0"], 4, "work-limit"),
        (vec![short_output.as_str()], 3, "output-limit"),
    ] {
        failure(&invoke(&options, row), status, message);
    }
    failure(
        &invoke(&["--max-scale=2"], b"a,1,1e-3,0\n"),
        3,
        "decimal-limit",
    );
    failure(
        &invoke(&["--max-digits=3"], b"a,999,999,0\n"),
        3,
        "decimal-limit",
    );
    let help = invoke(&["--help"], b"invalid");
    assert_eq!(help.status.code(), Some(0), "{help:?}");
    assert!(
        help.stdout.starts_with(b"Usage: decimal_ledger ")
            && help.stdout.ends_with(b"unnecessary\n")
            && help.stderr.is_empty(),
        "{help:?}"
    );
}
#[test]
fn ledger_large_batch_matches_reference_and_reports_native_observation() {
    let input = seeded_rows(512);
    let expected = oracle(2, "half-even", true, &input);
    let _ = executable();
    let started = Instant::now();
    let output = invoke(&["--header"], &input);
    let elapsed = started.elapsed();
    success(&output, &expected);
    eprintln!(
        "decimal ledger x86_64 Linux: 512 records, {} input bytes, {} output bytes, {:?} native wall time (includes process startup; excludes compilation)",
        input.len(),
        expected.len(),
        elapsed
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
fn ledger_releases_every_observed_allocation_on_denial_and_io_faults() {
    assert!(
        Command::new("strace")
            .arg("-V")
            .output()
            .unwrap()
            .status
            .success()
    );
    let input = b"\"invoice,\"\"\xc3\xa9\",-123456789012345.625,1.005,0.0825\n";
    let expected = oracle(2, "half-even", false, input);
    let data = file(input);
    let trace = common::TempArtifact::new("laniusc_decimal_ledger", "trace", None);
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
            .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())));
        assert_eq!(
            output.status.code(),
            Some(status),
            "injection={injection:?}: {output:?}"
        );
        if status == 0 {
            success(&output, &expected);
        } else {
            assert!(
                expected.starts_with(&output.stdout),
                "invalid output prefix: {output:?}"
            );
            assert!(
                output.stderr.starts_with(b"decimal_ledger: ") && output.stderr.ends_with(b"\n"),
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
            "allocation failure must precede all report output: {output:?}"
        );
    }
    let reads = events
        .lines()
        .filter(|line| line.starts_with("read("))
        .count();
    for when in 1..=reads {
        let (_, _, output) = execute(Some(&format!("read:error=EIO:when={when}")), 6);
        assert!(output.stdout.is_empty(), "{output:?}");
        execute(Some(&format!("read:error=EINTR:when={when}")), 0);
    }
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
    // strace suppresses the first transferred byte. Resume must emit exactly
    // the suffix once, so this catches writes that restart at the old offset.
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
    // The shared timeout helper captures its command's stdout, so redirect
    // inside the shell to exercise the actual /dev/full descriptor.
    let output = run(Command::new("sh")
        .args([
            "-c",
            "exec strace -qq -o \"$1\" -e trace=mmap,munmap,read,write \"$2\" <\"$3\" > /dev/full",
            "decimal_ledger",
        ])
        .arg(trace.path())
        .arg(executable().path())
        .arg(data.path()));
    failure(&output, 6, "io-failure");
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
}
