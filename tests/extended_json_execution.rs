mod common;
use laniusc_compiler::compiler::{compile_entry_to_x86_64_with_source_roots, EntrySourceRoots};

fn compile(path: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"))
}

fn executable(path: &str, name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let bytes = compile(path);
    let file = common::TempArtifact::new("laniusc_json", name, None);
    file.write_bytes(&bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}

fn run(executable: &common::TempArtifact, bytes: &[u8]) -> std::process::Output {
    let input = common::TempArtifact::new("laniusc_json", "input", None);
    input.write_bytes(bytes);
    common::short_process_output_with_timeout(
        "JSON execution",
        std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(input.path()).unwrap(),
        )),
    )
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn json_building_queries_limits_and_ownership_execute() {
    let bytes = compile("tests/fixtures/extended/json_contracts.lani");
    let output = common::run_x86_64_elf_output("JSON contracts", "contracts", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

fn next(seed: &mut u32) -> u32 {
    *seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
    *seed
}

fn generated_value(seed: &mut u32, depth: u32) -> serde_json::Value {
    let choice = next(seed) % if depth == 0 { 4 } else { 6 };
    let strings = [
        "",
        "a",
        "\0\n\r\t\u{1f}",
        "é🙂",
        "\"\\/",
        " spaced ",
        "\u{2028}\u{2029}",
    ];
    match choice {
        0 => serde_json::Value::Null,
        1 => serde_json::Value::Bool(next(seed) & 1 != 0),
        2 => serde_json::Value::from(next(seed) as i32),
        3 => serde_json::Value::from(strings[next(seed) as usize % strings.len()]),
        4 => {
            let count = next(seed) % 5;
            serde_json::Value::Array(
                (0..count)
                    .map(|_| generated_value(seed, depth - 1))
                    .collect(),
            )
        }
        _ => {
            let count = next(seed) % 5;
            let mut map = serde_json::Map::new();
            for index in 0..count {
                let key = format!("k{index}{}", strings[next(seed) as usize % strings.len()]);
                map.insert(key, generated_value(seed, depth - 1));
            }
            serde_json::Value::Object(map)
        }
    }
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn json_normalizer_executes_grammar_unicode_and_generated_round_trips() {
    let exe = executable("sample_programs/json_normalize.lani", "normalize");
    for (source, expected) in [
        ("null", "null"),
        (" \r\ntrue\t ", "true"),
        ("false", "false"),
        ("-0", "-0"),
        ("1.2300e+05", "1.2300e+05"),
        ("1e400", "1e400"),
        (
            "1844674407370955161600000000001",
            "1844674407370955161600000000001",
        ),
        (
            " [null, true, false, 1.5, {}, []] ",
            "[null,true,false,1.5,{},[]]",
        ),
        (r#"{"x":1,"x":2}"#, r#"{"x":1,"x":2}"#),
        (r#"{"a":1,"\u0061":2}"#, r#"{"a":1,"a":2}"#),
        (
            r#"{"": {"x":[1,{"y":2}]}, "z": []}"#,
            r#"{"":{"x":[1,{"y":2}]},"z":[]}"#,
        ),
        (r#""\u0061\u00E9\uD83D\uDE42""#, "\"aé🙂\""),
        (r#""\uDBFF\uDFFF""#, "\"\u{10ffff}\""),
        (
            r#""\/\b\f\n\r\t\"\\\u0000""#,
            r#""/\u0008\u000c\u000a\u000d\u0009\"\\\u0000""#,
        ),
        ("\"\u{7f}\u{2028}\u{2029}\"", "\"\u{7f}\u{2028}\u{2029}\""),
    ] {
        let output = run(&exe, source.as_bytes());
        assert_eq!(output.status.code(), Some(0), "{source:?}: {output:?}");
        assert_eq!(output.stdout, expected.as_bytes(), "{source:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    for source in [
        "",
        " ",
        "[",
        "{",
        "[1,]",
        "{\"a\":1,}",
        "{a:1}",
        "{\"a\" 1}",
        "[1 2]",
        "[}",
        "{]",
        "true false",
        "nullx",
        "True",
        "NaN",
        "Infinity",
        "+1",
        "01",
        "-01",
        "-",
        ".1",
        "0.",
        "1e",
        "1e+",
        "1E-",
        "1.2.3",
        "1x",
        "/*x*/0",
        "\"unterminated",
        "\"\\",
        r#""\q""#,
        r#""\u0""#,
        r#""\uZZZZ""#,
        r#""\uD800""#,
        r#""\uDC00""#,
        r#""\uD800\uD800""#,
        r#""\uDC00\uD800""#,
        r#""\uD800x""#,
        "\"a\nb\"",
        "\"a\0b\"",
        "\u{feff}null",
        "\u{a0}0",
    ] {
        let output = run(&exe, source.as_bytes());
        assert_eq!(output.status.code(), Some(2), "{source:?}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{source:?}: {output:?}"
        );
    }
    for invalid_utf8 in [
        &b"\"\xff\""[..],
        &b"\"\xed\xa0\x80\""[..],
        &b"\"\xf4\x90\x80\x80\""[..],
    ] {
        let output = run(&exe, invalid_utf8);
        assert_eq!(output.status.code(), Some(2), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
    }
    for depth in [128, 129] {
        let source = format!("{}null{}", "[".repeat(depth), "]".repeat(depth));
        let output = run(&exe, source.as_bytes());
        if depth == 128 {
            assert_eq!(output.status.code(), Some(0));
            assert_eq!(output.stdout, source.as_bytes());
        } else {
            assert_eq!(output.status.code(), Some(2));
            assert!(output.stdout.is_empty());
        }
    }
    let mut seed = 0x6a736f6e;
    for case in 0..96 {
        let value = generated_value(&mut seed, 4);
        let source = serde_json::to_vec_pretty(&value).unwrap();
        let output = run(&exe, &source);
        assert_eq!(
            output.status.code(),
            Some(0),
            "case {case}, seed {seed}: {value:?}: {output:?}"
        );
        let actual: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(actual, value, "case {case}");
        let repeated = run(&exe, &output.stdout);
        assert_eq!(repeated.status.code(), Some(0), "case {case}: {repeated:?}");
        assert_eq!(
            repeated.stdout, output.stdout,
            "case {case}: normalization is idempotent"
        );
    }
    let long = serde_json::json!({"text": "é🙂\n\\".repeat(2048), "numbers": (0..128).collect::<Vec<_>>()});
    let output = run(&exe, &serde_json::to_vec(&long).unwrap());
    assert_eq!(output.status.code(), Some(0), "long document: {output:?}");
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&output.stdout).unwrap(),
        long
    );
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn assert_all_allocations_freed(trace: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut allocations = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                let address = result.split_whitespace().next().unwrap().to_owned();
                assert!(live.insert(address), "duplicate live allocation: {line}");
                allocations += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let address = tail.split(',').next().unwrap();
            assert!(line.ends_with(" = 0"), "deallocation failed: {line}");
            assert!(live.remove(address), "unknown/double deallocation: {line}");
        }
    }
    assert!(live.is_empty(), "allocations leaked: {live:?}\n{trace}");
    allocations
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn json_frees_partial_results_at_every_allocation_failure() {
    let exe = executable(
        "tests/fixtures/extended/json_allocation_failure.lani",
        "failure",
    );
    let trace = common::TempArtifact::new("laniusc_json", "allocations", None);
    let baseline = common::short_process_output_with_timeout(
        "JSON allocations",
        std::process::Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(exe.path()),
    );
    assert_eq!(baseline.status.code(), Some(1), "{baseline:?}");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    let allocation_count = assert_all_allocations_freed(&events);
    assert!(
        allocation_count > 20,
        "fixture must exercise nested ownership: {events}"
    );
    for when in 2..=allocation_count {
        let failed = common::short_process_output_with_timeout(
            "JSON injected allocation failure",
            std::process::Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap", "-e"])
                .arg(format!("inject=mmap:error=ENOMEM:when={when}+"))
                .arg(exe.path()),
        );
        assert_eq!(
            failed.status.code(),
            Some(0),
            "allocation {when}: {failed:?}"
        );
        assert!(
            failed.stdout.is_empty() && failed.stderr.is_empty(),
            "{failed:?}"
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(
            events.contains("INJECTED") && events.contains("ENOMEM"),
            "{events}"
        );
        assert_all_allocations_freed(&events);
    }

    let normalizer = executable("sample_programs/json_normalize.lani", "failure_normalizer");
    let input = common::TempArtifact::new("laniusc_json", "malformed", None);
    // Fail after owning keys, values, nested containers, or a partial escape.
    for source in [
        r#"{"a":[1,"hello",{"b":"world"}],"unfinished"#,
        r#"{"a":[1,"hello"],"b" 0}"#,
        r#"{"a":[1,"hello"],"b":"partial\uZZZZ"}"#,
        r#"{"a":[1,"hello"],"b":"partial\uD800"}"#,
        r#"{"a":[1,"hello"],"b":}"#,
        r#"{"a":[1,"hello"],"b":01}"#,
        r#"{"a":[1,"hello"],}"#,
        r#"{"a":[1,"hello"]} trailing"#,
    ] {
        input.write_bytes(source.as_bytes());
        let output = common::short_process_output_with_timeout(
            "JSON malformed-input cleanup",
            std::process::Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap"])
                .arg(normalizer.path())
                .stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
        );
        assert_eq!(output.status.code(), Some(2), "{source:?}: {output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert_all_allocations_freed(&std::fs::read_to_string(trace.path()).unwrap());
    }
}
