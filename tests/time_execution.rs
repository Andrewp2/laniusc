#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
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
    let exe = common::TempArtifact::new("laniusc_time", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("time", command)
}
fn checked(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn numbers(bytes: &[u8]) -> Vec<u64> {
    std::str::from_utf8(bytes)
        .unwrap()
        .split_whitespace()
        .map(|v| v.parse().unwrap())
        .collect()
}
const BILLION: u128 = 1_000_000_000;
const MAX_DURATION: u128 = u64::MAX as u128 * BILLION + BILLION - 1;
fn duration(out: &mut Vec<u64>, value: Result<u128, u64>) {
    match value {
        Ok(n) if n <= MAX_DURATION => out.extend([0, (n / BILLION) as u64, (n % BILLION) as u64]),
        Ok(_) => out.extend([1, 0, 0]),
        Err(code) => out.extend([code, 0, 0]),
    }
}
fn scalar(out: &mut Vec<u64>, value: u128) {
    if value > u64::MAX as u128 {
        out.extend([1, 0]);
    } else {
        out.extend([0, value as u64]);
    }
}
fn timestamp(out: &mut Vec<u64>, value: i128) {
    let seconds = value.div_euclid(BILLION as i128);
    let nanos = value.rem_euclid(BILLION as i128);
    if seconds < i64::MIN as i128 || seconds > i64::MAX as i128 {
        out.extend([1, 0, 0]);
    } else {
        out.extend([0, seconds as i64 as u64, nanos as u64]);
    }
}
fn expected(a_sec: u64, a_nano: u32, b_sec: u64, b_nano: u32, factor: u32) -> Vec<u64> {
    let a = a_sec as u128 * BILLION + a_nano as u128;
    let b = b_sec as u128 * BILLION + b_nano as u128;
    let mut out = Vec::new();
    duration(&mut out, Ok(a_sec as u128 * BILLION + factor as u128));
    duration(&mut out, Ok(a + b));
    duration(&mut out, a.checked_sub(b).ok_or(2));
    duration(&mut out, Ok(a * factor as u128));
    duration(&mut out, a.checked_div(factor as u128).ok_or(3));
    duration(&mut out, Ok((a + b).min(MAX_DURATION)));
    duration(&mut out, Ok(a.saturating_sub(b)));
    duration(&mut out, Ok((a * factor as u128).min(MAX_DURATION)));
    scalar(&mut out, a / 1_000_000);
    scalar(&mut out, a / 1_000);
    scalar(&mut out, a);
    duration(&mut out, Ok(a_sec as u128 * BILLION));
    duration(&mut out, Ok(a_sec as u128 * 1_000_000));
    duration(&mut out, Ok(a_sec as u128 * 1_000));
    duration(&mut out, Ok(a_sec as u128));
    out.push(if a < b {
        0
    } else if a == b {
        1
    } else {
        2
    });
    duration(&mut out, a.checked_sub(b).ok_or(2));
    duration(&mut out, Ok(a.saturating_sub(b)));
    duration(&mut out, Ok(a + b));
    duration(&mut out, a.checked_sub(b).ok_or(2));
    duration(&mut out, Ok(a.saturating_sub(b)));
    out.push(u64::from(b >= a));
    let a_signed = a_sec as i64 as i128 * BILLION as i128 + a_nano as i128;
    let b_signed = b_sec as i64 as i128 * BILLION as i128 + b_nano as i128;
    duration(
        &mut out,
        if a_signed >= b_signed {
            Ok((a_signed - b_signed) as u128)
        } else {
            Err(2)
        },
    );
    timestamp(&mut out, a_signed + b as i128);
    timestamp(&mut out, a_signed - b as i128);
    out.push(if a_signed < b_signed {
        0
    } else if a_signed == b_signed {
        1
    } else {
        2
    });
    out
}
#[test]
fn portable_time_contracts_and_clock_simulation_execute_without_host_services() {
    for fixture in [
        "tests/fixtures/stdlib_foundation/time_contracts.lani",
        "tests/fixtures/stdlib_host/clock_contracts.lani",
    ] {
        let exe = executable(fixture);
        let trace = common::TempArtifact::new("laniusc_time", "pure_trace", None);
        let output = run(Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap,clock_gettime,nanosleep",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path()));
        checked(&output);
        assert!(output.stdout.is_empty());
        assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    }
}
#[test]
fn duration_and_signed_timestamp_arithmetic_match_wide_integer_model() {
    let exe = executable("tests/fixtures/stdlib_foundation/time_model.lani");
    let seconds = [
        0,
        1,
        2,
        18_446_744_073,
        18_446_744_074,
        u64::MAX / 1_000_000,
        u64::MAX / 1000,
        u64::MAX / 1000 + 1,
        i64::MAX as u64,
        1 << 63,
        u64::MAX - 1,
        u64::MAX,
    ];
    let fractions = [0, 1, 500_000_000, 999_999_999];
    let factors = [0, 1, 2, 3, 1_000_000_000, u32::MAX];
    let mut cases = Vec::new();
    for (i, &a) in seconds.iter().enumerate() {
        for (j, &b) in seconds.iter().enumerate() {
            cases.push((
                a,
                fractions[i % 4],
                b,
                fractions[j % 4],
                factors[(i + j) % 6],
            ));
        }
    }
    let mut state = 0x71ae2026_12345678_u64;
    let mut next = || {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        state
    };
    for _ in 0..256 {
        cases.push((
            next(),
            (next() % 1_000_000_000) as u32,
            next(),
            (next() % 1_000_000_000) as u32,
            next() as u32,
        ));
    }
    for (index, (a, an, b, bn, f)) in cases.into_iter().enumerate() {
        let output = run(Command::new(exe.path()).args([
            a.to_string(),
            an.to_string(),
            b.to_string(),
            bn.to_string(),
            f.to_string(),
        ]));
        checked(&output);
        assert_eq!(
            numbers(&output.stdout),
            expected(a, an, b, bn, f),
            "case={index} a=({a},{an}) b=({b},{bn}) factor={f}"
        );
    }
}

fn timespec_hex(seconds: i64, nanos: i64) -> String {
    seconds
        .to_le_bytes()
        .into_iter()
        .chain(nanos.to_le_bytes())
        .map(|b| format!("{b:02x}"))
        .collect()
}
fn clock_trace_values(events: &str) -> Vec<(i64, i64)> {
    events
        .lines()
        .filter(|line| line.starts_with("clock_gettime("))
        .filter_map(|line| {
            let (_, tail) = line.split_once("{tv_sec=")?;
            let (seconds, tail) = tail.split_once(", tv_nsec=").unwrap();
            let nanos = tail.split('}').next().unwrap();
            Some((seconds.parse().unwrap(), nanos.parse().unwrap()))
        })
        .collect()
}
#[test]
fn native_clocks_preserve_timespecs_errors_and_deadline_waits() {
    let exe = executable("tests/fixtures/stdlib_host/clock_native.lani");
    let trace = common::TempArtifact::new("laniusc_time", "native_trace", None);
    let invoke = |mode: &str, faults: &[String], code: u64| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,clock_gettime,nanosleep"]);
        for fault in faults {
            command.arg("-e").arg(format!("inject={fault}"));
        }
        let output = run(command.arg(exe.path()).arg(mode));
        checked(&output);
        let values = numbers(&output.stdout);
        assert_eq!(values.len(), 3);
        assert_eq!(values[0], code, "mode={mode}, faults={faults:?}");
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(
            !events.contains("mmap(") && !events.contains("munmap("),
            "{events}"
        );
        if !faults.is_empty() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        (values, events)
    };
    for (mode, clock) in [("0", "CLOCK_MONOTONIC"), ("1", "CLOCK_REALTIME")] {
        let (values, events) = invoke(mode, &[], 0);
        assert!(events.contains(clock));
        let actual = clock_trace_values(&events);
        assert_eq!(actual.len(), 1);
        assert_eq!(&values[1..], &[actual[0].0 as u64, actual[0].1 as u64]);
        assert!(values[2] < 1_000_000_000);
        for (fault, code) in [
            ("error=EIO", 5),
            ("error=EPERM", 1),
            ("error=EINTR", 4),
            ("retval=1", 1001),
        ] {
            invoke(mode, &[format!("clock_gettime:{fault}:when=1")], code);
        }
        for (seconds, nanos, code) in [
            (0, 0, 0),
            (i64::MAX, 999_999_999, 0),
            (i64::MIN, 1, if mode == "1" { 0 } else { 1000 }),
            (1, -1, 1000),
            (1, 1_000_000_000, 1000),
            (1, 1_i64 << 32, 1000),
        ] {
            let (values, _) = invoke(
                mode,
                &[format!(
                    "clock_gettime:retval=0:poke_exit=@arg2={}:when=1",
                    timespec_hex(seconds, nanos)
                )],
                code,
            );
            if code == 0 {
                assert_eq!(&values[1..], &[seconds as u64, nanos as u64]);
            }
        }
    }
    let start = std::time::Instant::now();
    let (_, events) = invoke("2", &[], 0);
    assert!(start.elapsed() >= std::time::Duration::from_millis(10));
    assert!(
        events.contains("nanosleep({tv_sec=0, tv_nsec=10000000}, NULL) = 0"),
        "{events}"
    );
    let (_, events) = invoke("2", &["nanosleep:error=EINTR:when=1".into()], 0);
    assert!(
        events
            .lines()
            .filter(|line| line.starts_with("nanosleep("))
            .count()
            >= 2
    );
    for (fault, code) in [
        ("nanosleep:error=EIO:when=1", 5),
        ("nanosleep:retval=1:when=1", 1001),
        ("clock_gettime:error=EIO:when=1", 5),
        ("clock_gettime:error=EIO:when=2", 5),
    ] {
        invoke("2", &[fault.into()], code);
    }
    let (_, events) = invoke("3", &[], 0);
    assert_eq!(clock_trace_values(&events).len(), 1);
    assert!(!events.contains("nanosleep("));
    let (_, events) = invoke("4", &[], 1002);
    assert!(events.is_empty());
    let (_, events) = invoke("5", &[], 0);
    assert!(
        events.contains("nanosleep({tv_sec=0, tv_nsec=1000000}, NULL) = 0"),
        "{events}"
    );
    let (values, events) = invoke("6", &["nanosleep:retval=0:when=1".into()], 0);
    assert_eq!(values[1], i32::MAX as u64);
    assert!(
        events.contains("nanosleep({tv_sec=2147483, tv_nsec=647000000}, NULL)"),
        "{events}"
    );
    let (_, events) = invoke(
        "7",
        &[
            "nanosleep:retval=0:when=1+".into(),
            "clock_gettime:error=EIO:when=2".into(),
        ],
        5,
    );
    assert!(
        events.contains("nanosleep({tv_sec=2147483, tv_nsec=647000000}, NULL)"),
        "{events}"
    );
    invoke(
        "2",
        &[
            format!(
                "clock_gettime:retval=0:poke_exit=@arg2={}:when=1",
                timespec_hex(i64::MAX, 0)
            ),
            "nanosleep:retval=0:when=1+".into(),
        ],
        1004,
    );
}

fn tick_records(bytes: &[u8]) -> Vec<serde_json::Value> {
    std::str::from_utf8(bytes)
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect()
}
fn validate_ticks(bytes: &[u8], count: usize, interval: u64) {
    let rows = tick_records(bytes);
    assert_eq!(rows.len(), count);
    let mut previous = 0;
    for (index, row) in rows.iter().enumerate() {
        assert_eq!(row.as_object().unwrap().len(), 5);
        assert_eq!(row["tick"], index);
        assert!(row["unix_seconds"].as_i64().is_some());
        assert!(row["nanoseconds"].as_u64().unwrap() < 1_000_000_000);
        let elapsed = row["elapsed_ns"].as_u64().unwrap();
        let late = row["late_ns"].as_u64().unwrap();
        assert!(elapsed >= previous);
        assert_eq!(elapsed, interval * 1_000_000 * index as u64 + late);
        previous = elapsed;
    }
}
#[test]
fn scheduled_ticks_report_absolute_deadlines_and_propagate_failures() {
    let exe = executable("sample_programs/clock_ticks.lani");
    let trace = common::TempArtifact::new("laniusc_time", "tick_trace", None);
    for (count, interval) in [(0, 0), (1, 0), (8, 0), (3, 2), (2, 10)] {
        let output = run(Command::new(exe.path()).args([count.to_string(), interval.to_string()]));
        checked(&output);
        validate_ticks(&output.stdout, count, interval);
    }
    let output = run(&mut Command::new(exe.path()));
    checked(&output);
    validate_ticks(&output.stdout, 3, 10);
    for args in [
        vec!["-1"],
        vec!["1001"],
        vec!["2", "60001"],
        vec!["0", "-1"],
        vec!["1", "0", "extra"],
        vec!["bad"],
        vec!["18446744073709551616"],
    ] {
        let output = run(Command::new(exe.path()).args(args));
        assert_eq!(output.status.code(), Some(2));
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
    }
    let invoke = |args: &[&str], fault: Option<String>, code: i32| {
        let mut command = Command::new("strace");
        command.args(["-qq", "-o"]).arg(trace.path()).args([
            "-e",
            "trace=mmap,munmap,clock_gettime,nanosleep,write",
            "-e",
            "inject=mmap:error=ENOMEM:when=1+",
        ]);
        if let Some(ref value) = fault {
            command.arg("-e").arg(format!("inject={value}"));
        }
        let output = run(command.arg(exe.path()).args(args));
        assert_eq!(output.status.code(), Some(code), "{output:?}");
        assert!(output.stderr.is_empty());
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(!events.contains("mmap(") && !events.contains("munmap("));
        if fault.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        (output, events)
    };
    let (output, events) = invoke(&["0", "0"], None, 0);
    assert!(output.stdout.is_empty() && events.is_empty());
    let (output, baseline) = invoke(&["3", "0"], None, 0);
    validate_ticks(&output.stdout, 3, 0);
    assert!(!baseline.contains("nanosleep("));
    for call in ["clock_gettime", "write"] {
        let count = baseline
            .lines()
            .filter(|line| line.starts_with(&format!("{call}(")))
            .count();
        assert!(count > 0);
        for when in 1..=count {
            let (output, _) = invoke(
                &["3", "0"],
                Some(format!("{call}:error=EIO:when={when}")),
                3,
            );
            assert!(tick_records(&output.stdout).len() < 3);
        }
    }
    let (output, _) = invoke(&["3", "0"], Some("write:error=EINTR:when=1".into()), 0);
    validate_ticks(&output.stdout, 3, 0);
    invoke(&["3", "0"], Some("write:retval=0:when=1".into()), 3);
}

#[test]
fn time_keys_compose_with_collections_and_large_batches_keep_precision() {
    let collection = executable("tests/fixtures/stdlib_foundation/time_collections.lani");
    let output = run(&mut Command::new(collection.path()));
    checked(&output);
    assert!(output.stdout.is_empty());
    let exe = executable("tests/fixtures/stdlib_foundation/time_batch.lani");
    let trace = common::TempArtifact::new("laniusc_time", "batch_trace", None);
    for (mode, count) in [(0, 0), (0, 1048576), (1, 128)] {
        let output = common::process_output_with_timeout(
            "time batch",
            Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args([
                    "-e",
                    "trace=clock_gettime,nanosleep,mmap,munmap",
                    "-e",
                    "inject=mmap:error=ENOMEM:when=1+",
                ])
                .arg(exe.path())
                .args([mode.to_string(), count.to_string()]),
            std::time::Duration::from_secs(5),
        );
        checked(&output);
        let values = numbers(&output.stdout);
        assert_eq!(values.len(), 1);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if mode == 0 {
            assert_eq!(values[0], 123456789 * count);
            assert!(events.is_empty());
        } else {
            assert!(
                !events.contains("mmap(")
                    && !events.contains("munmap(")
                    && !events.contains("nanosleep(")
            );
            let reads = clock_trace_values(&events);
            assert_eq!(reads.len(), count as usize + 1);
            let first = reads.first().unwrap();
            let last = reads.last().unwrap();
            assert_eq!(
                values[0],
                ((last.0 - first.0) * 1_000_000_000 + last.1 - first.1) as u64
            );
        }
    }
}
