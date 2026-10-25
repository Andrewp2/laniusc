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
    let exe = common::TempArtifact::new("laniusc_config", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("config", command)
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn freed(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let value = line.rsplit(" = ").next().unwrap();
            if value.starts_with("0x") {
                assert!(
                    live.insert(value.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "leaked allocations: {events}");
    count
}

#[test]
fn configuration_queries_preserve_types_precedence_and_borrowed_lifetimes() {
    let exe = executable("tests/fixtures/extended/config_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_config", "query_trace", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap,write"])
        .arg(exe.path()));
    checked(&output, 0);
    assert_eq!(output.stdout, b"Q");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(freed(&events) > 0);
    let marker = events.find("write(1,").unwrap();
    assert!(
        !events[marker..].contains("mmap("),
        "queries must not allocate: {events}"
    );
}

#[test]
fn borrowed_json_views_survive_node_growth_and_queries_do_not_allocate() {
    let exe = executable("tests/fixtures/extended/json_views.lani");
    let trace = common::TempArtifact::new("laniusc_config", "json_views_trace", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap,write"])
        .arg(exe.path()));
    checked(&output, 0);
    assert_eq!(output.stdout, b"Q");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(freed(&events) > 0);
    let marker = events.find("write(1,").unwrap();
    assert!(!events[marker..].contains("mmap("), "{events}");
}

#[test]
fn checksum_configuration_layers_validate_schema_and_yield_to_cli_overrides() {
    let exe = executable("sample_programs/checksum.lani");
    let input = common::TempArtifact::new("laniusc_config", "checksum_data", None);
    input.write_bytes(b"123456789");
    let low = common::TempArtifact::new("laniusc_config", "defaults", None);
    let high = common::TempArtifact::new("laniusc_config", "overrides", None);
    low.write_bytes(b"{\"decimal\":true,\"limit\":9.0}");
    high.write_bytes(b"{\"limit\":1e0}");
    let invoke = |args: &[std::ffi::OsString], status: i32, expected: &[u8]| {
        let output = run(Command::new(exe.path())
            .args(args)
            .stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )));
        checked(&output, status);
        assert_eq!(output.stdout, expected);
    };
    let low_path = low.path().as_os_str().to_os_string();
    let high_path = high.path().as_os_str().to_os_string();
    invoke(&["-c".into(), low_path.clone()], 0, b"3421780262\n");
    invoke(
        &[
            "-c".into(),
            low_path.clone(),
            "-c".into(),
            high_path.clone(),
        ],
        2,
        b"",
    );
    invoke(
        &[
            "-n9".into(),
            "-c".into(),
            low_path.clone(),
            "-c".into(),
            high_path.clone(),
            "--hex".into(),
        ],
        0,
        b"cbf43926\n",
    );
    invoke(
        &[
            "-c".into(),
            high_path.clone(),
            "-c".into(),
            low_path.clone(),
            "-xd".into(),
        ],
        0,
        b"3421780262\n",
    );
    high.write_bytes(b"{\"decimal\":false}");
    invoke(
        &[
            "-c".into(),
            low_path.clone(),
            "-c".into(),
            high_path.clone(),
        ],
        0,
        b"cbf43926\n",
    );
    for invalid in [
        b"{\"limti\":9}".as_slice(),
        b"{\"limit\":null}",
        b"{\"limit\":1.5}",
        b"{\"limit\":-1}",
        b"{\"limit\":18446744073709551616}",
        b"{\"decimal\":\"true\"}",
        b"{\"decimal\":true,\"decimal\":false}",
        b"{\"limit\":9,\"\\u006cimit\":0}",
        b"[]",
        b"\xff",
    ] {
        high.write_bytes(invalid);
        invoke(
            &["--limit=9".into(), "-c".into(), high_path.clone()],
            2,
            b"",
        );
    }
    high.write_bytes(b"{\"limit\":\"bad\"}");
    invoke(&["-c".into(), high_path, "-c".into(), low_path], 2, b"");
    invoke(
        &[
            "-c".into(),
            high.path()
                .with_extension("missing")
                .as_os_str()
                .to_os_string(),
        ],
        3,
        b"",
    );
}

#[test]
fn configured_checksum_releases_sources_when_any_allocation_or_io_step_fails() {
    let exe = executable("sample_programs/checksum.lani");
    let input = common::TempArtifact::new("laniusc_config", "configured_data", None);
    input.write_bytes(b"123456789");
    let low = common::TempArtifact::new("laniusc_config", "configured_low", None);
    low.write_bytes(b"{\"decimal\":true,\"limit\":1.0}");
    let high = common::TempArtifact::new("laniusc_config", "configured_high", None);
    high.write_bytes(b"{\"limit\":9e0}");
    let trace = common::TempArtifact::new("laniusc_config", "configured_trace", None);
    let expected = b"3421780262\n";
    let execute = |injection: Option<String>, status: i32| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,open,openat,read,write,close"]);
        if let Some(ref injection) = injection {
            command.arg("-e").arg(format!("inject={injection}"));
        }
        let output = run(command
            .arg(exe.path())
            .arg("-c")
            .arg(low.path())
            .arg("-c")
            .arg(high.path())
            .arg(input.path()));
        checked(&output, status);
        if status == 0 {
            assert_eq!(output.stdout, expected);
        } else {
            assert!(expected.starts_with(&output.stdout));
        }
        let events = std::fs::read_to_string(trace.path()).unwrap();
        freed(&events);
        file_handles_closed(&events);
        if injection.is_some() {
            assert!(events.contains("INJECTED"));
        }
        events
    };
    let baseline = execute(None, 0);
    let allocations = baseline
        .lines()
        .filter(|line| line.starts_with("mmap("))
        .count();
    assert!(
        allocations > 2,
        "exercise allocations beyond the argument snapshot"
    );
    assert_eq!(
        baseline
            .lines()
            .filter(|line| line.starts_with("open(") || line.starts_with("openat("))
            .count(),
        3,
        "open both configuration sources and the data file"
    );
    for when in 1..=allocations {
        execute(Some(format!("mmap:error=ENOMEM:when={when}+")), 4);
    }
    let open = if baseline.lines().any(|line| line.starts_with("openat(")) {
        "openat"
    } else {
        "open"
    };
    for call in [open, "read", "write", "close"] {
        let count = baseline
            .lines()
            .filter(|line| line.starts_with(&format!("{call}(")))
            .count();
        assert!(count > 0);
        for when in 1..=count {
            execute(Some(format!("{call}:error=EIO:when={when}")), 3);
        }
    }
}

fn integer_row(negative: bool, magnitude: u128, scale: i32) -> String {
    let magnitude = if scale < 0 {
        let divisor = 10_u128.pow((-scale) as u32);
        if magnitude % divisor != 0 {
            return "1 0 1 0".into();
        }
        Some(magnitude / divisor)
    } else {
        magnitude.checked_mul(10_u128.pow(scale as u32))
    };
    let Some(magnitude) = magnitude else {
        return "2 0 2 0".into();
    };
    let signed = if magnitude <= (i64::MAX as u128 + u128::from(negative)) {
        format!(
            "0 {}",
            if negative {
                -(magnitude as i128)
            } else {
                magnitude as i128
            }
        )
    } else {
        "2 0".into()
    };
    let unsigned = if magnitude <= u64::MAX as u128 && (!negative || magnitude == 0) {
        format!("0 {magnitude}")
    } else {
        "2 0".into()
    };
    format!("{signed} {unsigned}")
}

#[test]
fn exact_json_integer_conversion_matches_rational_values_and_extreme_exponents() {
    let exe = executable("tests/fixtures/extended/json_integers.lani");
    let input = common::TempArtifact::new("laniusc_config", "integers", None);
    let mut sources = Vec::new();
    let mut expected = Vec::new();
    for magnitude in [
        0,
        1,
        9,
        10,
        125,
        i64::MAX as u128,
        (i64::MAX as u128) + 1,
        u64::MAX as u128,
        (u64::MAX as u128) + 1,
        999999999999999999999999999999999999_u128,
    ] {
        for negative in [false, true] {
            for scale in [-18, -3, -1, 0, 1, 3, 18] {
                sources.push(format!(
                    "{}{magnitude}e{scale}",
                    if negative { "-" } else { "" }
                ));
                expected.push(integer_row(negative, magnitude, scale));
            }
        }
    }
    let mut seed = 0xc0f1_2026_u32;
    let mut random = || {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        seed
    };
    for _ in 0..512 {
        let coefficient = (u128::from(random()) << 32) | u128::from(random());
        let digits = coefficient.to_string();
        let decimal_at = (random() as usize) % (digits.len() + 1);
        let fraction = digits.len() - decimal_at;
        let mut mantissa = if decimal_at == 0 {
            format!("0.{digits}")
        } else if fraction == 0 {
            digits.clone()
        } else {
            format!("{}.{}", &digits[..decimal_at], &digits[decimal_at..])
        };
        if fraction > 0 && random() & 1 != 0 {
            mantissa.push_str("000");
        }
        let exponent = (random() % 25) as i32 - 12;
        let negative = random() & 1 != 0;
        sources.push(format!(
            "{}{mantissa}E{exponent:+}",
            if negative { "-" } else { "" }
        ));
        expected.push(integer_row(
            negative,
            coefficient,
            exponent - fraction as i32,
        ));
    }
    for (source, answer) in [
        ("1.0", "0 1 0 1"),
        ("-0.000e-999999999999", "0 0 0 0"),
        ("1e4294967296", "2 0 2 0"),
        ("1e-4294967296", "1 0 1 0"),
        ("18446744073709551615.0000", "2 0 0 18446744073709551615"),
        ("-9223372036854775808.000", "0 -9223372036854775808 2 0"),
        ("1844674407370955161500e-2", "2 0 0 18446744073709551615"),
        (
            "0.9223372036854775807e19",
            "0 9223372036854775807 0 9223372036854775807",
        ),
        ("null", "3 0 3 0"),
        ("true", "3 0 3 0"),
        ("\"12\"", "3 0 3 0"),
        ("[]", "3 0 3 0"),
        ("{}", "3 0 3 0"),
    ] {
        sources.push(source.to_owned());
        expected.push(answer.to_owned());
    }
    for (source, answer) in [
        (format!("1{}e-10000", "0".repeat(10000)), "0 1 0 1"),
        (format!("0.{}1e10000", "0".repeat(9999)), "0 1 0 1"),
        (format!("0e{}", "9".repeat(1000)), "0 0 0 0"),
        (format!("1e{}", "9".repeat(1000)), "2 0 2 0"),
        (format!("1e-{}", "9".repeat(1000)), "1 0 1 0"),
    ] {
        sources.push(source);
        expected.push(answer.to_owned());
    }
    input.write_bytes(format!("[{}]", sources.join(",")).as_bytes());
    let output = common::process_output_with_timeout(
        "JSON exact integers",
        Command::new(exe.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(input.path()).unwrap(),
        )),
        std::time::Duration::from_secs(5),
    );
    checked(&output, 0);
    let actual: Vec<_> = std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .collect();
    assert_eq!(actual.len(), expected.len());
    for (index, (actual, expected)) in actual.iter().zip(&expected).enumerate() {
        assert_eq!(
            actual, expected,
            "seed=0xc0f12026 case={index} source={}",
            sources[index]
        );
    }
}

fn file_handles_closed(events: &str) {
    let mut handles = std::collections::BTreeSet::new();
    for line in events.lines() {
        if line.starts_with("open(") || line.starts_with("openat(") {
            if let Some(value) = line
                .rsplit(" = ")
                .next()
                .and_then(|part| part.split_whitespace().next())
                .and_then(|value| value.parse::<i32>().ok())
                .filter(|&value| value >= 0)
            {
                assert!(handles.insert(value), "{events}");
            }
        } else if let Some(tail) = line.strip_prefix("close(") {
            let handle: i32 = tail.split(')').next().unwrap().parse().unwrap();
            assert!(handles.remove(&handle), "{events}");
        }
    }
    assert!(handles.is_empty(), "missing close attempt: {events}");
}

#[test]
fn file_loading_rejects_invalid_documents_and_enforces_each_limit() {
    let exe = executable("tests/fixtures/extended/config_load.lani");
    let input = common::TempArtifact::new("laniusc_config", "source", None);
    let trace = common::TempArtifact::new("laniusc_config", "load_trace", None);
    let cases: Vec<(&[u8], i32, i32, i32)> = vec![
        (b"{}", 2, 0, 0),
        (b"{}", 1, 0, 22),
        (b"{}", 0, 0, 22),
        (b"", 0, 0, 11),
        (b"{}", 2, 1, 12),
        (b"{}", 2, 2, 13),
        (b"{}", 2, 3, 14),
        (b"{\"x\":null}", 100, 4, 15),
        (b"{\"\":1}", 100, 5, 16),
        (b"{}", 2, 4, 0),
        (b"{\"x\":false}", 100, 0, 0),
        (b"null", 100, 0, 20),
        (b"[1]", 100, 0, 20),
        (b"true", 100, 0, 20),
        (b"{", 100, 0, 11),
        (b"{}x", 100, 0, 11),
        (b"\xff", 100, 0, 21),
        (b"{\"x\":1,\"x\":2}", 100, 0, 10),
        (b"{\"a\":1,\"\\u0061\":2}", 100, 0, 10),
        (b"{\"x\":{\"a\":1,\"a\":2}}", 100, 0, 10),
    ];
    for (case, (bytes, maximum, mode, status)) in cases.into_iter().enumerate() {
        input.write_bytes(bytes);
        let output = run(Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,open,openat,close"])
            .arg(exe.path())
            .arg(input.path())
            .arg(maximum.to_string())
            .arg(mode.to_string()));
        checked(&output, status);
        if status == 0 {
            let value: serde_json::Value = serde_json::from_slice(bytes).unwrap();
            assert_eq!(
                output.stdout,
                format!("{}\n", value.as_object().unwrap().len()).as_bytes()
            );
        } else {
            assert!(output.stdout.is_empty(), "case={case}");
        }
        let events = std::fs::read_to_string(trace.path()).unwrap();
        freed(&events);
        file_handles_closed(&events);
        if mode == 1 {
            assert!(!events
                .lines()
                .any(|l| l.starts_with("open(") || l.starts_with("openat(")));
        }
    }
    for (maximum, mode, status) in [(0, 0, 3), (-1, 0, 23), (0, 1, 12)] {
        let missing = input.path().with_extension("missing");
        let output = run(Command::new(exe.path())
            .arg(missing)
            .arg(maximum.to_string())
            .arg(mode.to_string()));
        checked(&output, status);
        assert!(output.stdout.is_empty());
    }
}

#[test]
fn loading_frees_partial_owners_at_every_allocation_and_host_failure() {
    let exe = executable("tests/fixtures/extended/config_load.lani");
    let input = common::TempArtifact::new("laniusc_config", "fault_source", None);
    let trace = common::TempArtifact::new("laniusc_config", "fault_trace", None);
    input.write_bytes("{\"limit\":9.0,\"decimal\":true,\"nested\":[1,{\"x\":\"é\"}]}".as_bytes());
    let execute = |injection: Option<String>, status: i32| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,open,openat,read,close"]);
        if let Some(ref injection) = injection {
            command.arg("-e").arg(format!("inject={injection}"));
        }
        let output = run(command
            .arg(exe.path())
            .arg(input.path())
            .args(["1024", "0"]));
        checked(&output, status);
        if status == 0 {
            assert_eq!(output.stdout, b"3\n");
        } else {
            assert!(output.stdout.is_empty());
        }
        let events = std::fs::read_to_string(trace.path()).unwrap();
        freed(&events);
        file_handles_closed(&events);
        if injection.is_some() {
            assert!(events.contains("INJECTED"));
        }
        events
    };
    let baseline = execute(None, 0);
    let allocations = baseline.lines().filter(|l| l.starts_with("mmap(")).count();
    assert!(allocations > 10);
    for when in 1..=allocations {
        execute(Some(format!("mmap:error=ENOMEM:when={when}+")), 4);
    }
    let open = if baseline.lines().any(|line| line.starts_with("openat(")) {
        "openat"
    } else {
        "open"
    };
    for call in [open, "read", "close"] {
        let count = baseline
            .lines()
            .filter(|line| line.starts_with(&format!("{call}(")))
            .count();
        assert!(count > 0);
        for when in 1..=count {
            execute(Some(format!("{call}:error=EIO:when={when}")), 3);
        }
    }
    execute(Some("read:error=EINTR:when=1".into()), 0);
    execute(Some("close:error=EINTR:when=1".into()), 3);
}

fn generated_value(random: &mut impl FnMut() -> u32, depth: u32) -> serde_json::Value {
    use serde_json::Value;
    match random() % if depth == 0 { 4 } else { 6 } {
        0 => Value::Null,
        1 => Value::Bool(random() & 1 != 0),
        2 => Value::from(random() as i32),
        3 => Value::from(["", "é😀", "x\0y", "\n\t\"\\", "value"][random() as usize % 5]),
        4 => Value::Array(
            (0..random() % 5)
                .map(|_| generated_value(random, depth - 1))
                .collect(),
        ),
        _ => {
            let mut map = serde_json::Map::new();
            for index in 0..random() % 5 {
                map.insert(
                    format!("k{index}{}", ["", "é", "\0", "/"][random() as usize % 4]),
                    generated_value(random, depth - 1),
                );
            }
            Value::Object(map)
        }
    }
}
fn reference_value(value: &serde_json::Value, origin: usize, output: &mut Vec<i32>) {
    use serde_json::Value;
    fn text(text: &str, output: &mut Vec<i32>) {
        output.push(text.len() as i32);
        output.extend(text.as_bytes().iter().map(|&b| i32::from(b)));
    }
    let kind = match value {
        Value::Null => 0,
        Value::Bool(_) => 1,
        Value::Number(_) => 2,
        Value::String(_) => 3,
        Value::Array(_) => 4,
        Value::Object(_) => 5,
    };
    output.extend([kind, origin as i32]);
    match value {
        Value::Null => {}
        Value::Bool(v) => output.push(i32::from(*v)),
        Value::Number(v) => text(&v.to_string(), output),
        Value::String(v) => text(v, output),
        Value::Array(items) => {
            output.push(items.len() as i32);
            for item in items {
                reference_value(item, origin, output);
            }
        }
        Value::Object(items) => {
            output.push(items.len() as i32);
            for (key, item) in items {
                text(key, output);
                reference_value(item, origin, output);
            }
        }
    }
}
#[test]
fn layered_queries_match_shallow_reference_over_generated_trees() {
    let exe = executable("tests/fixtures/extended/config_layers.lani");
    let files: Vec<_> = (0..4)
        .map(|_| common::TempArtifact::new("laniusc_config", "layer", None))
        .collect();
    let keys = ["", "a", "é😀", "x.y", "nested"];
    let mut seed = 0x1a9e_2026_u32;
    let mut random = || {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        seed
    };
    let mut kinds = [false; 6];
    for case in 0..64 {
        let count = case % 5;
        let mut reference = std::collections::BTreeMap::new();
        for (origin, file) in files.iter().take(count).enumerate() {
            let mut object = serde_json::Map::new();
            for key in keys {
                if (random() >> 16) % 3 != 0 {
                    let value = generated_value(&mut random, 3);
                    reference.insert(key, (origin, value.clone()));
                    object.insert(key.into(), value);
                }
            }
            file.write_bytes(&serde_json::to_vec(&object).unwrap());
        }
        for key in keys {
            let output = run(Command::new(exe.path())
                .args(files.iter().take(count).map(|file| file.path()))
                .arg(key));
            checked(&output, 0);
            let actual: Vec<i32> = std::str::from_utf8(&output.stdout)
                .unwrap()
                .split_ascii_whitespace()
                .map(|n| n.parse().unwrap())
                .collect();
            let mut expected = Vec::new();
            if let Some((origin, value)) = reference.get(key) {
                reference_value(value, *origin, &mut expected);
                kinds[expected[0] as usize] = true;
            } else {
                expected.push(-1);
            }
            assert_eq!(
                actual, expected,
                "seed=0x1a9e2026 case={case} query={key:?}"
            );
        }
    }
    assert!(kinds.into_iter().all(|seen| seen));
}
