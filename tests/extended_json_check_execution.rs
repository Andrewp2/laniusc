#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    ffi::OsStr,
    os::unix::{ffi::OsStrExt, fs::PermissionsExt},
    path::Path,
    process::{Command, Output, Stdio},
    time::Duration,
};

fn executable() -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/json_check.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("json-check", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("json-check: {error}"));
    let exe = common::TempArtifact::new("laniusc_json_check", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("json-check", command, Duration::from_secs(10))
}
fn file(bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_json_check", "data", Some("json"));
    file.write_bytes(bytes);
    file
}
fn invoke_path(
    exe: &common::TempArtifact,
    options: &[&str],
    schema: &Path,
    input: &[u8],
) -> Output {
    let data = file(input);
    run(Command::new(exe.path())
        .args(options)
        .arg("--")
        .arg(schema)
        .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())))
}
fn invoke(exe: &common::TempArtifact, options: &[&str], schema: &[u8], input: &[u8]) -> Output {
    let schema = file(schema);
    invoke_path(exe, options, schema.path(), input)
}
fn checked(output: &Output, status: i32, diagnostic: &str) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stdout.is_empty(), "{output:?}");
    if status == 0 {
        assert!(output.stderr.is_empty(), "{output:?}");
    } else {
        let message = std::str::from_utf8(&output.stderr).unwrap();
        assert!(
            message.starts_with("json-check: ")
                && message.ends_with('\n')
                && message.contains(diagnostic),
            "{output:?}"
        );
    }
}

const CONFIG: &[u8] = br##"{
  "type":"object",
  "$defs":{"port":{"type":"integer","minimum":1,"maximum":65535}},
  "properties":{
    "host":{"type":"string","minLength":1,"maxLength":40},
    "port":{"$ref":"#/$defs/port"},
    "mode":{"enum":["dev","prod"]},
    "tags":{"type":"array","items":{"type":"string","minLength":1},"minItems":1,"maxItems":5},
    "enabled":{"type":"boolean"}
  },
  "required":["host","port","mode"],"additionalProperties":false
}"##;

#[test]
fn json_check_executes_real_configuration_refs_unicode_and_exact_decimal_constraints() {
    let exe = executable();
    let valid = "{\"host\":\"é🙂\",\"port\":443,\"mode\":\"prod\",\"tags\":[\"one\",\"two\"],\"enabled\":true}";
    checked(&invoke(&exe, &[], CONFIG, valid.as_bytes()), 0, "");
    for (input, keyword) in [
        (
            br#"{"host":"a","port":0,"mode":"dev"}"#.as_slice(),
            "minimum",
        ),
        (
            br#"{"host":"a","port":65536,"mode":"dev"}"#.as_slice(),
            "maximum",
        ),
        (
            br#"{"host":"a","port":2.5,"mode":"dev"}"#.as_slice(),
            "type",
        ),
        (br#"{"port":80,"mode":"dev"}"#.as_slice(), "required"),
        (
            br#"{"host":"a","port":80,"mode":"other"}"#.as_slice(),
            "enum",
        ),
        (
            br#"{"host":"a","port":80,"mode":"dev","extra":1}"#.as_slice(),
            "false",
        ),
        (
            br#"{"host":"a","port":80,"mode":"dev","tags":[]}"#.as_slice(),
            "minItems",
        ),
    ] {
        let output = invoke(&exe, &[], CONFIG, input);
        checked(&output, 1, &format!("keyword={keyword}"));
        let diagnostic = std::str::from_utf8(&output.stderr).unwrap();
        assert!(diagnostic.contains("schema-node=") && diagnostic.contains("instance-node="));
    }
    let string_schema = br#"{"type":"string","minLength":2,"maxLength":2}"#;
    checked(
        &invoke(&exe, &[], string_schema, "\"é🙂\"".as_bytes()),
        0,
        "",
    );
    checked(
        &invoke(&exe, &[], string_schema, br#""\u00e9\ud83d\ude42""#),
        0,
        "",
    );
    checked(
        &invoke(&exe, &[], string_schema, "\"🙂\"".as_bytes()),
        1,
        "keyword=minLength",
    );
    checked(
        &invoke(&exe, &[], string_schema, "\"é🙂x\"".as_bytes()),
        1,
        "keyword=maxLength",
    );
    let exact=br#"{"type":"number","minimum":123456789012345678901234567890.00001,"maximum":123456789012345678901234567890.00003}"#;
    for value in [
        b"123456789012345678901234567890.00001".as_slice(),
        b"123456789012345678901234567890.00002",
        b"123456789012345678901234567890.00003",
        b"12345678901234567890123456789000002e-5",
    ] {
        checked(&invoke(&exe, &[], exact, value), 0, "");
    }
    checked(
        &invoke(&exe, &[], exact, b"123456789012345678901234567890.000009"),
        1,
        "keyword=minimum",
    );
    checked(
        &invoke(&exe, &[], exact, b"123456789012345678901234567890.000031"),
        1,
        "keyword=maximum",
    );
    checked(&invoke(&exe, &[], b"false", b"null"), 1, "schema-violation");
    checked(
        &invoke(
            &exe,
            &[],
            br#"{"propertyNames":{"minLength":2}}"#,
            br#"{"a":0}"#,
        ),
        1,
        "property-name=true",
    );
    checked(&invoke(&exe, &[], b"true", b"[null,true,{},[]]"), 0, "");
}

#[test]
fn json_check_rejects_invalid_schema_instance_duplicate_keys_and_resource_limits() {
    let exe = executable();
    for (schema, input, diagnostic) in [
        (
            b"{".as_slice(),
            b"null".as_slice(),
            "invalid-json stage=schema",
        ),
        (
            b"{\"type\":\"object\",\"type\":\"string\"}".as_slice(),
            b"null".as_slice(),
            "duplicate-key",
        ),
        (
            br#"{"$defs":{"unused":{"type":3}}}"#.as_slice(),
            b"not-json".as_slice(),
            "invalid-schema",
        ),
        (
            br#"{"properties":{"unused":{"pattern":"a"}}}"#.as_slice(),
            b"{}".as_slice(),
            "invalid-schema",
        ),
        (
            br##"{"$ref":"https://example.invalid/schema"}"##.as_slice(),
            b"null".as_slice(),
            "invalid-schema",
        ),
        (
            br#"{"$schema":"unknown"}"#.as_slice(),
            b"null".as_slice(),
            "invalid-schema",
        ),
        (
            b"true".as_slice(),
            b"{\"a\":1,\"\\u0061\":2}".as_slice(),
            "duplicate-key",
        ),
        (
            b"true".as_slice(),
            b"[1,]".as_slice(),
            "invalid-json stage=instance",
        ),
        (
            b"true".as_slice(),
            b"\"\xff\"".as_slice(),
            "invalid-utf8 stage=instance",
        ),
        (
            b"true".as_slice(),
            br#""\ud800""#.as_slice(),
            "invalid-json stage=instance",
        ),
    ] {
        checked(&invoke(&exe, &[], schema, input), 2, diagnostic);
    }
    for options in [
        vec!["--max-schema-bytes=3"],
        vec!["--max-input-bytes=1"],
        vec!["--max-nodes=0"],
        vec!["--max-work=0"],
    ] {
        checked(
            &invoke(&exe, &options, br#"{"type":"number"}"#, b"42"),
            2,
            "",
        );
    }
    checked(
        &invoke(
            &exe,
            &["--max-scratch-bytes=0"],
            br#"{"multipleOf":0.01}"#,
            b"0.5",
        ),
        2,
        "resource-limit",
    );
    checked(
        &invoke(
            &exe,
            &["--max-schema-bytes=4", "--max-input-bytes=2"],
            b"true",
            b"42",
        ),
        0,
        "",
    );
    checked(
        &invoke(
            &exe,
            &["--max-schema-bytes=4", "--max-input-bytes=2"],
            b"true",
            b"42 ",
        ),
        2,
        "resource-limit",
    );
    checked(
        &invoke(&exe, &["--max-depth=1"], b"true", b"[[[0]]]"),
        2,
        "resource-limit",
    );
    let input = file(b"null");
    for options in [
        vec![],
        vec!["--bad"],
        vec!["--max-depth=129"],
        vec!["--max-input-bytes=-1"],
        vec!["--max-work=1000000001"],
        vec!["--max-work=+1"],
        vec!["--max-nodes=1000001"],
        vec!["--help=yes"],
    ] {
        let output = run(Command::new(exe.path())
            .args(&options)
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
        checked(&output, 2, "invalid-arguments");
    }
    let schema = file(br#"{"$defs":{"unused":{"type":3}}}"#);
    let trace = common::TempArtifact::new("laniusc_json_check", "early_schema", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap,open,openat,close,read"])
        .arg(exe.path())
        .arg(schema.path())
        .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
    checked(&output, 2, "invalid-schema");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        !events.lines().any(|line| line.starts_with("read(0,")),
        "{events}"
    );
    no_leaks(&events);
}

fn oracle(schema: &Path, input: &Path) -> Option<bool> {
    let script = "import sys,json,decimal\ntry: import jsonschema\nexcept ImportError: sys.exit(77)\nwith open(sys.argv[1]) as f: schema=json.load(f,parse_float=decimal.Decimal)\nwith open(sys.argv[2]) as f: instance=json.load(f,parse_float=decimal.Decimal)\nprint(int(jsonschema.Draft202012Validator(schema).is_valid(instance)))\n";
    let output = run(Command::new("python3")
        .args(["-c", script])
        .arg(schema)
        .arg(input));
    if output.status.code() == Some(77) {
        return None;
    }
    assert!(
        output.status.success() && output.stderr.is_empty(),
        "{output:?}"
    );
    Some(output.stdout == b"1\n")
}

#[test]
fn json_check_matches_python_schema_oracle_and_reads_non_utf8_file_paths() {
    let exe = executable();
    let schema = file(CONFIG);
    for index in 0..24 {
        let port = if index % 5 == 0 { 0 } else { index * 3000 + 1 };
        let mode = if index % 4 == 0 { "other" } else { "prod" };
        let source = format!(
            "{{\"host\":\"example\",\"port\":{port},\"mode\":\"{mode}\",\"tags\":[\"one\",\"two\"]}}"
        );
        let data = file(source.as_bytes());
        let Some(valid) = oracle(schema.path(), data.path()) else {
            eprintln!("python jsonschema unavailable; independent oracle skipped");
            break;
        };
        checked(
            &invoke_path(&exe, &[], schema.path(), source.as_bytes()),
            if valid { 0 } else { 1 },
            "",
        );
    }
    let binary_path = schema
        .path()
        .with_extension(OsStr::from_bytes(b"\xff.schema"));
    std::fs::rename(schema.path(), &binary_path).unwrap();
    let output = invoke_path(
        &exe,
        &[],
        &binary_path,
        br#"{"host":"example","port":80,"mode":"dev"}"#,
    );
    std::fs::remove_file(&binary_path).unwrap();
    checked(&output, 0, "");
    let array_schema=br#"{"type":"array","items":{"type":"integer","minimum":0,"maximum":100000},"minItems":5000,"maxItems":5000}"#;
    let array = (0..5000)
        .map(|i| i.to_string())
        .collect::<Vec<_>>()
        .join(",");
    let source = format!("[{array}]");
    checked(
        &invoke(
            &exe,
            &["--max-work=100000000"],
            array_schema,
            source.as_bytes(),
        ),
        0,
        "",
    );
}

fn no_leaks(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut handles = std::collections::BTreeSet::new();
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
        } else if line.starts_with("open(") || line.starts_with("openat(") {
            let result = line
                .rsplit(" = ")
                .next()
                .unwrap()
                .split_whitespace()
                .next()
                .unwrap()
                .parse::<i32>()
                .unwrap();
            if result >= 0 {
                assert!(handles.insert(result), "{events}");
            }
        } else if let Some(tail) = line.strip_prefix("close(") {
            let fd = tail.split(')').next().unwrap().parse::<i32>().unwrap();
            if fd >= 3 {
                assert!(handles.remove(&fd), "{events}");
            }
        }
    }
    assert!(
        live.is_empty() && handles.is_empty(),
        "unreleased owners: {events}"
    );
    allocations
}

#[test]
fn json_check_releases_owners_on_every_observed_allocation_and_host_io_failure() {
    let exe = executable();
    // multipleOf requires real allocated decimal scratch, so this baseline
    // covers that owner as well as JSON trees, a local ref and compiled indexes.
    let schema = file(br##"{"type":"object","$defs":{"port":{"type":"integer","minimum":1}},"properties":{"port":{"$ref":"#/$defs/port"},"ratio":{"type":"number","multipleOf":0.01},"text":{"type":"string","minLength":1}},"required":["port","ratio","text"],"additionalProperties":false}"##);
    let data = file("{\"port\":443,\"ratio\":1.25,\"text\":\"é🙂\"}".as_bytes());
    let trace = common::TempArtifact::new("laniusc_json_check", "trace", None);
    let execute = |injection: Option<&str>, status| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,open,openat,close,read,write"]);
        if let Some(fault) = injection {
            command.arg("-e").arg(format!("inject={fault}"));
        }
        let output = run(command
            .arg(exe.path())
            .arg(schema.path())
            .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())));
        checked(&output, status, "");
        let events = std::fs::read_to_string(trace.path()).unwrap();
        let allocations = no_leaks(&events);
        if injection.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        (allocations, events)
    };
    let (allocations, events) = execute(None, 0);
    assert!(allocations >= 10, "{events}");
    for when in 1..=allocations {
        execute(Some(&format!("mmap:error=ENOMEM:when={when}")), 4);
    }
    let reads = events
        .lines()
        .filter(|line| line.starts_with("read("))
        .count();
    for when in 1..=reads {
        execute(Some(&format!("read:error=EIO:when={when}")), 3);
    }
    execute(Some("read:error=EINTR:when=1"), 0);
    execute(Some("read:error=EAGAIN:when=1"), 3);
    for syscall in ["open", "close"] {
        execute(Some(&format!("{syscall}:error=EIO:when=1")), 3);
    }
    for fault in ["write:error=EIO:when=1", "write:retval=0:when=1"] {
        let output = run(Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,write", "-e"])
            .arg(format!("inject={fault}"))
            .arg(exe.path())
            .arg("--help"));
        checked(&output, 3, "io-failure");
        no_leaks(&std::fs::read_to_string(trace.path()).unwrap());
    }
    // The normal validator is quiet; diagnostic output is its ordinary write
    // path. Failure to report a violation becomes I/O status 3 after cleanup.
    schema.write_bytes(b"false");
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap,open,openat,close,read,write",
            "-e",
            "inject=write:error=EIO:when=1",
        ])
        .arg(exe.path())
        .arg(schema.path())
        .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())));
    assert_eq!(output.status.code(), Some(3), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    no_leaks(&std::fs::read_to_string(trace.path()).unwrap());
}
