#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    sync::OnceLock,
    time::{Duration, Instant},
};

fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: Vec::new(),
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_float_format", "executable", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn app() -> &'static common::TempArtifact {
    static APP: OnceLock<common::TempArtifact> = OnceLock::new();
    APP.get_or_init(|| executable("sample_programs/library/float_normalize.lani"))
}
fn invoke(args: &[&str], bytes: &[u8]) -> Output {
    let input = common::TempArtifact::new("laniusc_float_format", "input", None);
    input.write_bytes(bytes);
    common::process_output_with_timeout(
        "float-normalize",
        Command::new(app().path())
            .args(args)
            .stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(20),
    )
}
fn success(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn injected(args: &[&str], bytes: &[u8], fault: &str) -> (Output, String) {
    let input = common::TempArtifact::new("laniusc_float_format", "input", None);
    input.write_bytes(bytes);
    let trace = common::TempArtifact::new("laniusc_float_format", "trace", None);
    let output = common::process_output_with_timeout(
        "float-normalize injected I/O",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=read,write,mmap,munmap,brk", "-e", fault])
            .arg(app().path())
            .args(args)
            .stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(20),
    );
    (output, std::fs::read_to_string(trace.path()).unwrap())
}

#[test]
fn display_composes_both_float_widths_custom_records_measurement_and_atomic_appends() {
    let exe = executable("tests/fixtures/stdlib_foundation/format_float_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_float_format", "trace", None);
    let output = common::process_output_with_timeout(
        "float Display contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap,brk,open,openat,socket,connect",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    success(&output);
    assert!(output.stdout.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}

#[test]
fn decimal_streaming_and_square_roots_match_native_primitives_at_both_widths() {
    let mut values = vec![
        "0".to_string(),
        "-0".into(),
        "+.5".into(),
        "1.".into(),
        "001.2500".into(),
        "1.0000000000000002".into(),
        "9007199254740993".into(),
        "2.2250738585072014e-308".into(),
        "4.9406564584124654e-324".into(),
        "1.7976931348623157e308".into(),
        "1e999999".into(),
        "-1e-999999".into(),
        "NaN".into(),
        "-Infinity".into(),
    ];
    let mut seed = 0xf10a_2026_77ef_0123_u64;
    for _ in 0..256 {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        let value = f64::from_bits(seed);
        if value.is_finite() {
            values.push(format!("{value:e}"));
        }
    }
    let input = values.join("\r\n") + "\r"; // Final CRLF-style record without LF.
    for narrow in [false, true] {
        for square_root in [false, true] {
            let mut args = Vec::new();
            if narrow {
                args.push("--f32");
            }
            if square_root {
                args.push("--sqrt");
            }
            let output = invoke(&args, input.as_bytes());
            success(&output);
            let text = std::str::from_utf8(&output.stdout).unwrap();
            let lines: Vec<_> = text.lines().collect();
            assert_eq!(lines.len(), values.len());
            for (index, (source, formatted)) in values.iter().zip(lines).enumerate() {
                if narrow {
                    let mut expected: f32 = source.parse().unwrap();
                    if square_root {
                        expected = expected.sqrt();
                    }
                    let got: f32 = formatted.parse().unwrap();
                    assert!(
                        (got.is_nan() && expected.is_nan()) || got.to_bits() == expected.to_bits(),
                        "case {index}: {source} -> {formatted}, expected {expected:?}, args={args:?}"
                    );
                } else {
                    let mut expected: f64 = source.parse().unwrap();
                    if square_root {
                        expected = expected.sqrt();
                    }
                    let got: f64 = formatted.parse().unwrap();
                    assert!(
                        (got.is_nan() && expected.is_nan()) || got.to_bits() == expected.to_bits(),
                        "case {index}: {source} -> {formatted}, expected {expected:?}, args={args:?}"
                    );
                }
            }
            let canonical_args = if narrow { vec!["--f32"] } else { Vec::new() };
            let repeated = invoke(&canonical_args, &output.stdout);
            success(&repeated);
            assert_eq!(repeated.stdout, output.stdout);
        }
    }
    let output = invoke(&[], b"1.5000\n-0\n1e20\n5e-324\nNaN\n");
    success(&output);
    assert_eq!(output.stdout, b"1.5\n-0\n1e20\n5e-324\nNaN\n");
}

#[test]
fn line_and_digit_limits_invalid_numbers_and_arguments_report_errors_without_bad_records() {
    success(&invoke(&[], b""));
    for bytes in [
        b"\n".as_slice(),
        b" \n",
        b"1 \n",
        b"1\0\n",
        b"1e\n",
        b".\n",
        b"--1\n",
    ] {
        let output = invoke(&[], bytes);
        assert_eq!(output.status.code(), Some(2), "{bytes:?}: {output:?}");
        assert!(output.stdout.is_empty());
        assert!(String::from_utf8_lossy(&output.stderr).contains("invalid"));
    }
    for (count, expected) in [(768, 0), (769, 2)] {
        let mut input = vec![b'0'; count];
        input.extend_from_slice(b"\r\n");
        let output = invoke(&[], &input);
        assert_eq!(output.status.code(), Some(expected), "{count}: {output:?}");
        if expected == 0 {
            assert_eq!(output.stdout, b"0\n");
        } else {
            assert!(output.stdout.is_empty());
        }
    }
    for (count, expected) in [(1024, 0), (1025, 2)] {
        let mut input = b"1e".to_vec();
        input.resize(count, b'9');
        input.extend_from_slice(b"\r\n");
        let output = invoke(&[], &input);
        assert_eq!(output.status.code(), Some(expected), "{count}: {output:?}");
        if expected == 0 {
            assert_eq!(output.stdout, b"inf\n");
        } else {
            assert!(output.stdout.is_empty());
        }
    }
    for args in [vec!["--finite-only"], vec!["--sqrt", "--finite-only"]] {
        let output = invoke(
            &args,
            if args.len() == 1 {
                b"1e9999\n"
            } else {
                b"-1\n"
            },
        );
        assert_eq!(output.status.code(), Some(2));
        assert!(output.stdout.is_empty());
    }
    let output = invoke(&[], b"2.50\nnope\n3\n");
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(output.stdout, b"2.5\n");
    for args in [
        vec!["--bad"],
        vec!["--f32", "--f32"],
        vec!["--help", "--sqrt"],
        vec!["input"],
    ] {
        let output = invoke(&args, b"1\n");
        assert_eq!(output.status.code(), Some(2));
        assert!(output.stdout.is_empty());
    }
    let output = invoke(&["--help"], b"bad");
    success(&output);
    assert!(String::from_utf8_lossy(&output.stdout).starts_with("Usage: float-normalize"));
}

#[test]
fn streaming_uses_no_allocation_retries_interrupts_and_reports_host_failures() {
    let (output, trace) = injected(&[], b"1.5000\n", "inject=mmap:error=ENOMEM:when=1+");
    success(&output);
    assert_eq!(output.stdout, b"1.5\n");
    assert!(
        !trace.contains("mmap(") && !trace.contains("munmap(") && !trace.contains("brk("),
        "{trace}"
    );
    for fault in [
        "inject=read:error=EINTR:when=1",
        "inject=write:error=EINTR:when=1",
    ] {
        let (output, trace) = injected(&[], b"2.500\n", fault);
        success(&output);
        assert_eq!(output.stdout, b"2.5\n");
        assert!(trace.contains("INJECTED"), "{trace}");
    }
    for fault in [
        "inject=read:error=EIO:when=1",
        "inject=write:error=EIO:when=1",
        "inject=write:retval=0:when=1",
    ] {
        let (output, trace) = injected(&[], b"2.500\n", fault);
        assert_eq!(output.status.code(), Some(3), "{output:?} {trace}");
        assert!(output.stdout.is_empty());
        assert!(String::from_utf8_lossy(&output.stderr).contains("I/O failed"));
    }
    let (output, _) = injected(&["--help"], b"", "inject=write:error=EIO:when=1");
    assert_eq!(output.status.code(), Some(3));
    assert!(output.stdout.is_empty());
}

#[test]
fn native_stream_scale_has_checked_round_trips() {
    let input = "1.25\n-0\n3.141592653589793\n1e-300\n".repeat(256);
    let _ = app(); // Compilation is outside the native process timing.
    let start = Instant::now();
    let output = invoke(&[], input.as_bytes());
    let elapsed = start.elapsed();
    success(&output);
    assert_eq!(output.stdout, input.as_bytes());
    eprintln!(
        "float-normalize: 1024 records, {} input bytes, {} output bytes, native process {:.3} ms",
        input.len(),
        output.stdout.len(),
        elapsed.as_secs_f64() * 1000.0
    );
}
