#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
};
fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_format_log", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("format/log", command)
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn formatting_composes_custom_types_and_latches_atomic_append_errors_without_allocation() {
    let exe = executable("tests/fixtures/stdlib_foundation/format_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_format_log", "allocations", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap",
            "-e",
            "inject=mmap:error=ENOMEM:when=1+",
        ])
        .arg(exe.path()));
    checked(&output, 0);
    assert!(output.stdout.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}
fn radix_string(
    mut magnitude: u64,
    negative: bool,
    base: u32,
    width: usize,
    uppercase: bool,
) -> String {
    let mut digits = Vec::new();
    loop {
        let digit = char::from_digit((magnitude % u64::from(base)) as u32, base).unwrap();
        digits.push(if uppercase {
            digit.to_ascii_uppercase()
        } else {
            digit
        });
        magnitude /= u64::from(base);
        if magnitude == 0 {
            break;
        }
    }
    while digits.len() < width {
        digits.push('0');
    }
    if negative {
        digits.push('-');
    }
    digits.iter().rev().collect()
}
#[test]
fn integer_formatting_matches_reference_for_all_radices_boundaries_and_padding() {
    let exe = executable("tests/fixtures/stdlib_foundation/format_input.lani");
    let mut state = 0xf04a_2026_1234_5678_u64;
    let mut cases = Vec::new();
    for base in 2..=36 {
        for value in [
            0,
            1,
            u64::from(base) - 1,
            u64::from(base),
            i64::MAX as u64,
            1 << 63,
            u64::MAX,
        ] {
            cases.push((value, base));
        }
    }
    for _ in 0..128 {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        cases.push((state, 2 + (state % 35) as u32));
    }
    for (index, (value, base)) in cases.into_iter().enumerate() {
        let width = [0, 1, 8, 20, 70][index % 5];
        let uppercase = index % 2 != 0;
        for signed in [false, true] {
            let negative = signed && (value as i64) < 0;
            let magnitude = if signed {
                (value as i64).unsigned_abs()
            } else {
                value
            };
            let number = if signed {
                (value as i64).to_string()
            } else {
                value.to_string()
            };
            let expected = radix_string(magnitude, negative, base, width, uppercase);
            let output = run(Command::new(exe.path()).args([
                if signed { "s" } else { "u" },
                &number,
                &base.to_string(),
                &width.to_string(),
                if uppercase { "1" } else { "0" },
            ]));
            checked(&output, 0);
            assert_eq!(
                output.stdout,
                expected.as_bytes(),
                "case {index}, signed={signed}, base={base}"
            );
        }
    }
    for (base, width) in [(0, 0), (1, 1), (37, 1), (10, -1), (10, i32::MAX)] {
        let output = run(Command::new(exe.path()).args([
            "u",
            "1",
            &base.to_string(),
            &width.to_string(),
            "0",
        ]));
        checked(&output, 2);
        assert!(output.stdout.is_empty());
    }
}

#[test]
fn quoted_utf8_round_trips_control_bytes_and_generated_scalars() {
    let exe = executable("tests/fixtures/stdlib_foundation/format_input.lani");
    let input = common::TempArtifact::new("laniusc_format_log", "text", None);
    let mut cases = vec![
        String::new(),
        (0_u8..=127).map(char::from).collect(),
        "é€🦅\u{2028}\u{2029}\u{10ffff}".into(),
    ];
    let mut state = 0xcafe2026_u32;
    for _ in 0..64 {
        let mut value = String::new();
        for _ in 0..96 {
            state = state.wrapping_mul(1664525).wrapping_add(1013904223);
            let cp = match state % 4 {
                0 => state % 32,
                1 => state % 128,
                _ => state % 0x110000,
            };
            if let Some(c) = char::from_u32(cp) {
                value.push(c);
            }
        }
        cases.push(value);
    }
    for (index, text) in cases.into_iter().enumerate() {
        input.write_bytes(text.as_bytes());
        let output = run(Command::new(exe.path())
            .arg("q")
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
        checked(&output, 0);
        let decoded: String = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(decoded, text, "case {index}");
        assert!(output.stdout.iter().all(|b| *b >= 32));
    }
    for bytes in [
        b"\xff".as_slice(),
        b"\xc0\x80",
        b"\xed\xa0\x80",
        b"\xf4\x90\x80\x80",
        b"\xe2\x82",
    ] {
        input.write_bytes(bytes);
        let output = run(Command::new(exe.path())
            .arg("q")
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
        checked(&output, 2);
        assert!(output.stdout.is_empty());
    }
}

#[test]
fn logging_encodes_filters_and_transfers_to_memory() {
    let exe = executable("tests/fixtures/extended/log_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_format_log", "log_allocations", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap",
            "-e",
            "inject=mmap:error=ENOMEM:when=1+",
        ])
        .arg(exe.path()));
    checked(&output, 0);
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    assert_eq!(output.stdout.iter().filter(|b| **b == b'\n').count(), 2);
    let actual = records(&output.stdout);
    assert_eq!(
        actual,
        vec![
            serde_json::json!({"level":"info","target":"test","message":"\0\n\r\"\\é\t","fields":{"text":"\0\n\r\"\\é\t","bool":false,"signed":i64::MIN,"unsigned":u64::MAX,"":null,"\0\n\r\"\\é\t":null}}),
            serde_json::json!({"level":"info","target":"","message":"","fields":{}})
        ]
    );
}

fn records(bytes: &[u8]) -> Vec<serde_json::Value> {
    serde_json::Deserializer::from_slice(bytes)
        .into_iter()
        .map(Result::unwrap)
        .collect()
}
fn record(level: &str, message: &str, input: i32, status: i32) -> serde_json::Value {
    serde_json::json!({"level":level,"target":"checksum","message":message,"fields":{"input":input,"status":status}})
}

#[test]
fn checksum_logging_obeys_config_overrides_filters_and_input_failures() {
    let exe = executable("sample_programs/checksum.lani");
    let input = common::TempArtifact::new("laniusc_format_log", "input", None);
    input.write_bytes(b"123456789");
    let config = common::TempArtifact::new("laniusc_format_log", "config", None);
    config.write_bytes(br#"{"log_level":"info"}"#);
    let config_path = config.path().to_str().unwrap();
    let input_path = input.path().to_str().unwrap();
    let invoke = |args: &[&str],
                  status: i32,
                  expected_stdout: &[u8],
                  expected_records: Vec<serde_json::Value>| {
        let output = run(Command::new(exe.path())
            .args(args)
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
        assert_eq!(output.status.code(), Some(status), "{args:?}: {output:?}");
        assert_eq!(output.stdout, expected_stdout, "{args:?}");
        assert_eq!(records(&output.stderr), expected_records, "{args:?}");
    };
    let success = record("info", "input_complete", 0, 0);
    invoke(&["-linfo"], 0, b"cbf43926\n", vec![success.clone()]);
    invoke(
        &["-ltrace", input_path, input_path],
        0,
        b"cbf43926\ncbf43926\n",
        vec![success.clone(), record("info", "input_complete", 1, 0)],
    );
    invoke(&["-lwarn"], 0, b"cbf43926\n", vec![]);
    invoke(
        &["--log-level", "error", "-n0"],
        2,
        b"",
        vec![record("error", "input_failed", 0, 2)],
    );
    invoke(&["-loff", "-n0"], 2, b"", vec![]);
    invoke(&["-linfo", "-loff"], 0, b"cbf43926\n", vec![]);
    invoke(
        &["-c", config_path],
        0,
        b"cbf43926\n",
        vec![success.clone()],
    );
    invoke(&["-loff", "-c", config_path], 0, b"cbf43926\n", vec![]);
    invoke(&["-c", config_path, "-loff"], 0, b"cbf43926\n", vec![]);
    let absent = format!("{input_path}.missing");
    invoke(
        &["-lwarn", input_path, &absent],
        3,
        b"cbf43926\n",
        vec![record("error", "input_failed", 1, 3)],
    );
    for value in ["INFO", "warning", " warn", "warn ", ""] {
        invoke(&["-l", value], 2, b"", vec![]);
    }
    for json in [
        r#"{"log_level":null}"#,
        r#"{"log_level":true}"#,
        r#"{"log_level":1}"#,
        r#"{"log_level":"INFO"}"#,
    ] {
        config.write_bytes(json.as_bytes());
        invoke(&["-c", config_path, "-linfo"], 2, b"", vec![]);
    }
    config.write_bytes(br#"{"log_level":"off","decimal":true}"#);
    invoke(
        &["-c", config_path, "-linfo"],
        0,
        b"3421780262\n",
        vec![success],
    );
}

fn released(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut handles = std::collections::BTreeSet::new();
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
        } else if line.starts_with("open(") || line.starts_with("openat(") {
            if let Some(handle) = line
                .rsplit(" = ")
                .next()
                .and_then(|part| part.split_whitespace().next())
                .and_then(|value| value.parse::<i32>().ok())
                .filter(|value| *value >= 0)
            {
                assert!(handles.insert(handle), "{events}");
            }
        } else if let Some(tail) = line.strip_prefix("close(") {
            let handle: i32 = tail.split(')').next().unwrap().parse().unwrap();
            assert!(handles.remove(&handle), "{events}");
        }
    }
    assert!(live.is_empty(), "{events}");
    assert!(handles.is_empty(), "missing close attempt: {events}");
    count
}
#[test]
fn checksum_logging_handles_write_errors_and_releases_owners_under_faults() {
    let exe = executable("sample_programs/checksum.lani");
    let input = common::TempArtifact::new("laniusc_format_log", "fault_input", None);
    input.write_bytes(b"123456789");
    let config = common::TempArtifact::new("laniusc_format_log", "fault_config", None);
    config.write_bytes(br#"{"log_level":"info"}"#);
    let trace = common::TempArtifact::new("laniusc_format_log", "fault_trace", None);
    let execute = |injection: Option<String>, status: i32| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,open,openat,read,write,close"]);
        if let Some(ref fault) = injection {
            command.arg("-e").arg(format!("inject={fault}"));
        }
        let output = run(command
            .arg(exe.path())
            .arg("-c")
            .arg(config.path())
            .arg(input.path()));
        assert_eq!(
            output.status.code(),
            Some(status),
            "{injection:?}: {output:?}"
        );
        assert!(b"cbf43926\n".starts_with(&output.stdout));
        let parsed = records(&output.stderr);
        if status == 0 {
            assert_eq!(output.stdout, b"cbf43926\n");
            assert_eq!(parsed, vec![record("info", "input_complete", 0, 0)]);
        } else {
            assert!(
                parsed.is_empty() || parsed == vec![record("error", "input_failed", 0, status)],
                "{injection:?}: {parsed:?}"
            );
        }
        let events = std::fs::read_to_string(trace.path()).unwrap();
        released(&events);
        if injection.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        events
    };
    let baseline = execute(None, 0);
    for when in 1..=baseline.lines().filter(|s| s.starts_with("mmap(")).count() {
        execute(Some(format!("mmap:error=ENOMEM:when={when}+")), 4);
    }
    let open = if baseline.lines().any(|s| s.starts_with("openat(")) {
        "openat"
    } else {
        "open"
    };
    for call in [open, "read", "write", "close"] {
        for when in 1..=baseline
            .lines()
            .filter(|s| s.starts_with(&format!("{call}(")))
            .count()
        {
            execute(Some(format!("{call}:error=EIO:when={when}")), 3);
        }
    }
    // First output is the checksum; the second is the log record.
    execute(Some("write:error=EINTR:when=2".into()), 0);
    execute(Some("write:retval=0:when=2".into()), 3);
}

#[test]
fn repeated_logging_reuses_storage_without_allocations_or_stale_fields() {
    let exe = executable("tests/fixtures/extended/log_batch.lani");
    let trace = common::TempArtifact::new("laniusc_format_log", "batch_trace", None);
    for count in [0, 128, 8192] {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path())
            .arg(count.to_string());
        let output = common::process_output_with_timeout(
            "bounded logging batch",
            &mut command,
            std::time::Duration::from_secs(5),
        );
        checked(&output, 0);
        assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
        let parsed = records(&output.stdout);
        assert_eq!(parsed.len(), count);
        for (index, actual) in parsed.into_iter().enumerate() {
            assert_eq!(
                actual,
                serde_json::json!({"level":"info","target":"batch","message":"item","fields":{"n":index}})
            );
        }
    }
}
