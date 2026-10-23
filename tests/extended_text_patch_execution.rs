#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeSet,
    ffi::OsString,
    os::unix::{ffi::OsStringExt, fs::PermissionsExt},
    process::{Command, Output, Stdio},
    sync::OnceLock,
    time::{Duration, Instant},
};

fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/text_patch.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("text-patch", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("text-patch: {error}"));
        let exe = common::TempArtifact::new("laniusc_text_patch", "executable", None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}

fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("text-patch", command, Duration::from_secs(30))
}
fn file(bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_text_patch", "data", None);
    file.write_bytes(bytes);
    file
}
fn args(values: &[&str]) -> Vec<OsString> {
    values.iter().map(OsString::from).collect()
}
fn invoke(arguments: &[OsString], input: &[u8]) -> Output {
    let source = file(input);
    run(Command::new(executable().path())
        .args(arguments)
        .stdin(Stdio::from(std::fs::File::open(source.path()).unwrap())))
}
fn diff(before: &[u8], after: &[u8], flags: &[&str]) -> Output {
    let old = file(before);
    let new = file(after);
    let mut arguments = args(&["diff"]);
    arguments.extend(args(flags));
    arguments.extend([old.path().into(), new.path().into()]);
    invoke(&arguments, b"")
}
fn apply(mode: &str, patch: &[u8], base: &[u8], flags: &[&str]) -> Output {
    let patch = file(patch);
    let mut arguments = args(&[mode]);
    arguments.extend(args(flags));
    arguments.push(patch.path().into());
    invoke(&arguments, base)
}
#[track_caller]
fn success(output: &Output, code: i32, expected: &[u8]) {
    assert_eq!(output.status.code(), Some(code), "{output:?}");
    assert_eq!(output.stdout, expected, "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
#[track_caller]
fn failure(output: &Output, code: i32, reason: &str) {
    assert_eq!(output.status.code(), Some(code), "{output:?}");
    assert!(
        output.stdout.is_empty(),
        "recoverable failure published output: {output:?}"
    );
    let message = std::str::from_utf8(&output.stderr).unwrap();
    assert!(
        message.starts_with("text-patch: ") && message.ends_with('\n') && message.contains(reason),
        "{output:?}"
    );
}

// Python and GNU are independent test oracles. The tested executable receives
// no tool paths or oracle output when producing its own diff.
fn python_diff(before: &[u8], after: &[u8], context: usize) -> Vec<u8> {
    let old = file(before);
    let new = file(after);
    let output = run(Command::new("python3")
        .args([
            "-c",
            r#"
import difflib, pathlib, sys
def lines(data):
    parts = data.split(b'\n')
    return [part + b'\n' for part in parts[:-1]] + ([parts[-1]] if parts[-1] else [])
before, after = (pathlib.Path(path).read_bytes() for path in sys.argv[1:3])
for row in difflib.diff_bytes(difflib.unified_diff, lines(before), lines(after),
                            fromfile=b'before', tofile=b'after', n=int(sys.argv[3])):
    sys.stdout.buffer.write(row)
    if not row.endswith(b'\n'):
        sys.stdout.buffer.write(b'\n\\ No newline at end of file\n')
"#,
        ])
        .arg(old.path())
        .arg(new.path())
        .arg(context.to_string()));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    output.stdout
}
fn gnu_diff(before: &[u8], after: &[u8], context: usize) -> Vec<u8> {
    let old = file(before);
    let new = file(after);
    let output = run(Command::new("diff")
        .args([
            "--binary",
            "--text",
            "--label=before",
            "--label=after",
            "-U",
        ])
        .arg(context.to_string())
        .arg(old.path())
        .arg(new.path()));
    assert_eq!(
        output.status.code(),
        Some(i32::from(before != after)),
        "{output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
    output.stdout
}
fn gnu_apply(patch: &[u8], base: &[u8], expected: &[u8]) {
    let source = file(base);
    let patch = file(patch);
    let target = common::TempArtifact::new("laniusc_text_patch", "gnu_result", None);
    let output = run(Command::new("patch")
        .args([
            "--binary",
            "--batch",
            "--silent",
            "--fuzz=0",
            "--no-backup-if-mismatch",
            "--output",
        ])
        .arg(target.path())
        .arg(source.path())
        .arg(patch.path()));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(
        std::fs::read(target.path()).unwrap(),
        expected,
        "{output:?}"
    );
}

#[test]
fn byte_exact_roundtrips_interoperate_with_python_and_gnu_unified_patches() {
    let mut cases = vec![
        (b"".to_vec(), b"".to_vec()),
        (b"same\n".to_vec(), b"same\n".to_vec()),
        (b"same".to_vec(), b"same".to_vec()),
        (b"".to_vec(), b"new\n".to_vec()),
        (b"old\n".to_vec(), b"".to_vec()),
        (b"old".to_vec(), b"new".to_vec()),
        (b"old\n".to_vec(), b"new".to_vec()),
        (b"old".to_vec(), b"new\n".to_vec()),
        (b"line\n".to_vec(), b"line".to_vec()),
        (b"line".to_vec(), b"line\n".to_vec()),
        (b"\n\n".to_vec(), b"\n".to_vec()),
        (
            b"a\r\nb\r\nc\rinside\r\n".to_vec(),
            b"a\r\nB\r\nc\rinside\r\n".to_vec(),
        ),
        (
            b"\xff\0old\n\x80tail".to_vec(),
            b"\xff\0new\n\x81tail".to_vec(),
        ),
        (b"a\nb\na\nb\na\n".to_vec(), b"b\na\nb\na\nb\n".to_vec()),
        (b"a\n\n\nb\n\n".to_vec(), b"\na\n\nb\n\n\n".to_vec()),
    ];
    let mut seed = 0x7061_7463_u32;
    let mut random = || {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        seed
    };
    let pool: [&[u8]; 7] = [
        b"a\n",
        b"b\n",
        b"a\n",
        b"\n",
        b"\xff\0\n",
        b"cr\r\n",
        b"x\ry\n",
    ];
    for case in 0..36 {
        let mut old = Vec::new();
        let mut new = Vec::new();
        for _ in 0..(random() % 16) {
            let line = pool[random() as usize % pool.len()];
            old.extend_from_slice(line);
            if random() % 4 != 0 {
                new.extend_from_slice(line);
            }
            if random() % 3 == 0 {
                new.extend_from_slice(pool[random() as usize % pool.len()]);
            }
        }
        if case % 3 == 0 && old.last() == Some(&b'\n') {
            old.pop();
        }
        if case % 4 == 0 && new.last() == Some(&b'\n') {
            new.pop();
        }
        cases.push((old, new));
    }
    for (index, (old, new)) in cases.iter().enumerate() {
        let context = [0, 1, 3, 8][index % 4];
        let native = diff(old, new, &["-U", &context.to_string()]);
        assert_eq!(
            native.status.code(),
            Some(i32::from(old != new)),
            "case {index}: {native:?}"
        );
        assert!(native.stderr.is_empty(), "case {index}: {native:?}");
        success(&apply("apply", &native.stdout, old, &[]), 0, new);
        success(&apply("check", &native.stdout, old, &[]), 0, b"");
        for independent in [python_diff(old, new, context), gnu_diff(old, new, context)] {
            success(&apply("apply", &independent, old, &[]), 0, new);
            success(&apply("check", &independent, old, &[]), 0, b"");
        }
        if old != new {
            assert!(
                native.stdout.starts_with(b"--- before\n+++ after\n@@ "),
                "{native:?}"
            );
            gnu_apply(&native.stdout, old, new);
        } else {
            assert!(native.stdout.is_empty(), "{native:?}");
        }
    }
}

#[test]
fn context_names_and_exact_patch_conflicts_preserve_staged_output() {
    let old = b"zero\none\ntwo\nthree\nfour\nfive\nsix\nseven\neight\n";
    let new = b"zero\nONE\ntwo\nthree\nfour\nfive\nsix\nSEVEN\neight\n";
    let zero = diff(old, new, &["-U0"]);
    success(
        &zero,
        1,
        b"--- before\n+++ after\n@@ -2,1 +2,1 @@\n-one\n+ONE\n@@ -8,1 +8,1 @@\n-seven\n+SEVEN\n",
    );
    let joined = diff(
        old,
        new,
        &["--context=3", "--old-name=old name", "--new-name=new name"],
    );
    assert_eq!(joined.status.code(), Some(1), "{joined:?}");
    assert!(joined.stderr.is_empty(), "{joined:?}");
    assert!(joined.stdout.starts_with(b"--- old name\n+++ new name\n"));
    assert_eq!(
        joined
            .stdout
            .windows(4)
            .filter(|bytes| *bytes == b"@@ -")
            .count(),
        1
    );
    success(&apply("apply", &joined.stdout, old, &[]), 0, new);
    let before = file(old);
    let after = file(new);
    let named = invoke(
        &[
            "diff".into(),
            "--old-name".into(),
            OsString::from_vec(b"old-\xff\x01\x7f".to_vec()),
            "--new-name".into(),
            OsString::from_vec(b"new-\x80\x1b".to_vec()),
            before.path().into(),
            after.path().into(),
        ],
        b"",
    );
    assert_eq!(named.status.code(), Some(1), "{named:?}");
    assert!(named.stderr.is_empty(), "{named:?}");
    assert!(named
        .stdout
        .starts_with(b"--- old-\xff\x01\x7f\n+++ new-\x80\x1b\n"));
    success(&apply("apply", &named.stdout, old, &[]), 0, new);
    for mode in ["apply", "check"] {
        let late_conflict = b"zero\none\ntwo\nthree\nfour\nfive\nsix\nWRONG\neight\n";
        failure(
            &apply(mode, &zero.stdout, late_conflict, &[]),
            2,
            "conflict",
        );
        let shifted = [b"prefix\n".as_slice(), old].concat();
        failure(&apply(mode, &zero.stdout, &shifted, &[]), 2, "conflict");
        // An empty patch is identity, including arbitrary bytes and no final LF.
        success(
            &apply(mode, b"", b"\xff\0\r\nlast", &[]),
            0,
            if mode == "apply" {
                b"\xff\0\r\nlast"
            } else {
                b""
            },
        );
        for malformed in [
            b"not a patch\n".as_slice(),
            b"--- a\n+++ b\n@@ -1 +1 @@\n-a\n",
            b"--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b\ntrailing garbage\n",
            b"--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b\n--- c\n+++ d\n@@ -1 +1 @@\n-c\n+d\n",
            b"--- a\n+++ b\n@@ -2147483648 +1 @@\n-a\n+b\n",
            b"--- a\n+++ b\n@@ -0 +1 @@\n-a\n+b\n",
            b"--- a\n+++ b\n@@ -1 +1 @@\n a\n",
            b"--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b",
            b"--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b\n\\ No newline at end of file\n+junk\n",
        ] {
            failure(&apply(mode, malformed, b"a\n", &[]), 2, "invalid-patch");
        }
    }
}

#[test]
fn all_cli_cap_ranges_and_effective_limits_are_checked_before_output() {
    let empty = file(b"");
    let valid = |flags: &[&str]| {
        let mut arguments = args(&["diff"]);
        arguments.extend(args(flags));
        arguments.extend([empty.path().into(), empty.path().into()]);
        invoke(&arguments, b"")
    };
    for (option, maximum) in [
        ("--max-input-bytes", 67_108_864_u64),
        ("--max-output-bytes", 67_108_864),
        ("--max-lines", 1_000_000),
        ("--max-trace-cells", 67_108_864),
        ("--max-edits", 2_000_000),
        ("--context", 67_108_864),
        ("--max-work", u64::MAX),
    ] {
        success(&valid(&[option, &maximum.to_string()]), 0, b"");
        if maximum < u64::MAX {
            failure(
                &valid(&[option, &(maximum + 1).to_string()]),
                2,
                "invalid-arguments",
            );
        }
        for invalid in ["", "-1", "1x", "18446744073709551616"] {
            failure(&valid(&[option, invalid]), 2, "invalid-arguments");
        }
    }
    for flags in [
        vec!["--max-input-bytes=0"],
        vec!["--max-output-bytes=0"],
        vec!["--max-lines=0"],
        vec!["--max-edits=0"],
        vec!["-U0"],
    ] {
        success(&valid(&flags), 0, b"");
    }
    for flags in [vec!["--max-work=0"], vec!["--max-trace-cells=0"]] {
        failure(&valid(&flags), 2, "resource-limit");
    }
    // Each file has its own byte limit; their combined size may exceed it.
    let changed = diff(b"a\n", b"b\n", &["--max-input-bytes=2", "--max-lines=1"]);
    assert_eq!(changed.status.code(), Some(1), "{changed:?}");
    assert!(changed.stderr.is_empty(), "{changed:?}");
    failure(
        &diff(b"a\n", b"b\n", &["--max-input-bytes=1"]),
        2,
        "resource-limit",
    );
    failure(
        &diff(b"a\n", b"b\n", &["--max-lines=0"]),
        2,
        "resource-limit",
    );
    failure(
        &diff(b"a\n", b"b\n", &["--max-edits=1"]),
        2,
        "resource-limit",
    );
    success(
        &diff(b"a\n", b"b\n", &["--max-edits=2"]),
        1,
        &changed.stdout,
    );
    for limit in [changed.stdout.len(), changed.stdout.len() + 1] {
        success(
            &diff(b"a\n", b"b\n", &[&format!("--max-output-bytes={limit}")]),
            1,
            &changed.stdout,
        );
    }
    failure(
        &diff(
            b"a\n",
            b"b\n",
            &[&format!("--max-output-bytes={}", changed.stdout.len() - 1)],
        ),
        2,
        "resource-limit",
    );
    failure(
        &diff(b"a\nb\n", b"a\nb\n", &["--max-lines=1"]),
        2,
        "resource-limit",
    );
    success(&diff(b"a\nb\n", b"a\nb\n", &["--max-lines=2"]), 0, b"");
    for mode in ["apply", "check"] {
        success(
            &apply(
                mode,
                &changed.stdout,
                b"a\n",
                &["--max-output-bytes=2", "--max-lines=1"],
            ),
            0,
            if mode == "apply" { b"b\n" } else { b"" },
        );
        for flags in [
            vec!["--max-output-bytes=1"],
            vec!["--max-lines=0"],
            vec!["--max-work=0"],
        ] {
            failure(
                &apply(mode, &changed.stdout, b"a\n", &flags),
                2,
                "resource-limit",
            );
        }
        let exact = format!("--max-input-bytes={}", changed.stdout.len());
        success(
            &apply(mode, &changed.stdout, b"a\n", &[&exact]),
            0,
            if mode == "apply" { b"b\n" } else { b"" },
        );
        failure(
            &apply(
                mode,
                &changed.stdout,
                b"a\n",
                &[&format!("--max-input-bytes={}", changed.stdout.len() - 1)],
            ),
            2,
            "resource-limit",
        );
        success(
            &apply(mode, b"", b"abc", &["--max-input-bytes=3"]),
            0,
            if mode == "apply" { b"abc" } else { b"" },
        );
        failure(
            &apply(mode, b"", b"abcd", &["--max-input-bytes=3"]),
            2,
            "resource-limit",
        );
        for diff_only in [
            "--context=0",
            "-U0",
            "--old-name=a",
            "--new-name=b",
            "--max-trace-cells=1",
            "--max-edits=2",
        ] {
            failure(
                &apply(mode, &changed.stdout, b"a\n", &[diff_only]),
                2,
                "invalid-arguments",
            );
        }
    }
    // Budget thresholds are discovered through the public interface. Every
    // larger budget must preserve the result; one below the first success fails.
    for option in ["--max-work", "--max-trace-cells"] {
        let mut low = 0_u64;
        let mut high = 4096_u64;
        success(
            &diff(b"a\n", b"b\n", &[&format!("{option}={high}")]),
            1,
            &changed.stdout,
        );
        while high - low > 1 {
            let mid = (low + high) / 2;
            let output = diff(b"a\n", b"b\n", &[&format!("{option}={mid}")]);
            if output.status.code() == Some(1) {
                success(&output, 1, &changed.stdout);
                high = mid;
            } else {
                failure(&output, 2, "resource-limit");
                low = mid;
            }
        }
        failure(
            &diff(b"a\n", b"b\n", &[&format!("{option}={low}")]),
            2,
            "resource-limit",
        );
        success(
            &diff(b"a\n", b"b\n", &[&format!("{option}={high}")]),
            1,
            &changed.stdout,
        );
    }
}

#[test]
fn invalid_arguments_and_argument_snapshot_boundaries_do_not_open_inputs() {
    for invalid in [
        vec![],
        vec!["unknown"],
        vec!["diff"],
        vec!["apply"],
        vec!["check"],
        vec!["--unknown"],
        vec!["--help=yes"],
        vec!["-Z"],
        vec!["--old-name"],
        vec!["diff", "missing", "missing", "extra"],
        vec!["apply", "missing", "extra"],
        vec!["check", "missing", "extra"],
        vec!["diff", "missing", "missing", "--unknown"],
        vec!["diff", "missing", "missing", "--old-name="],
        vec!["diff", "missing", "missing", "--new-name="],
    ] {
        failure(&invoke(&args(&invalid), b""), 2, "invalid-arguments");
    }
    for forbidden in [b'\t', b'\r', b'\n'] {
        for flag in ["--old-name", "--new-name"] {
            let mut arguments = args(&["diff", "missing", "missing", flag]);
            arguments.push(OsString::from_vec(vec![b'a', forbidden, b'b']));
            failure(&invoke(&arguments, b""), 2, "invalid-arguments");
        }
    }
    // execve forbids embedded NUL in argv; NUL payload bytes are exercised in
    // the independent diff/apply cases above.
    let help = invoke(&args(&["--help"]), b"");
    assert_eq!(help.status.code(), Some(0), "{help:?}");
    assert!(
        help.stderr.is_empty() && help.stdout.starts_with(b"Usage: text-patch "),
        "{help:?}"
    );
    success(
        &invoke(&vec![OsString::from("--help"); 32], b""),
        0,
        &help.stdout,
    );
    failure(
        &invoke(&vec![OsString::from("--help"); 33], b""),
        2,
        "invalid-arguments",
    );
    let mut boundary = args(&["--help", "--old-name"]);
    let used: usize = boundary
        .iter()
        .map(|value| value.as_encoded_bytes().len())
        .sum();
    boundary.push("x".repeat(8192 - used).into());
    success(&invoke(&boundary, b""), 0, &help.stdout);
    *boundary.last_mut().unwrap() = "x".repeat(8193 - used).into();
    failure(&invoke(&boundary, b""), 2, "invalid-arguments");
    for mode in ["diff", "apply", "check"] {
        let mut arguments = args(&[mode, "/this/path/does/not/exist/text-patch-input"]);
        if mode == "diff" {
            arguments.push("/another/missing/text-patch-input".into());
        }
        failure(&invoke(&arguments, b""), 3, "io-failure");
    }
}

fn cleanup(events: &str) -> usize {
    let mut live = BTreeSet::new();
    let mut handles = BTreeSet::new();
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
            if let Some(handle) = line
                .rsplit(" = ")
                .next()
                .and_then(|value| value.split_whitespace().next())
                .and_then(|value| value.parse::<i32>().ok())
                .filter(|&value| value >= 0)
            {
                assert!(handles.insert(handle), "{events}");
            }
        } else if let Some(tail) = line.strip_prefix("close(") {
            let handle: i32 = tail.split(')').next().unwrap().parse().unwrap();
            assert!(
                handles.remove(&handle),
                "unexpected or repeated close attempt: {events}"
            );
        }
    }
    assert!(live.is_empty(), "unreleased allocation owners: {events}");
    assert!(handles.is_empty(), "missing close attempts: {events}");
    allocations
}

fn traced(arguments: &[OsString], input: &[u8], fault: Option<&str>) -> (Output, String) {
    let source = file(input);
    let trace = common::TempArtifact::new("laniusc_text_patch", "syscalls", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap,open,openat,close,read,write"]);
    if let Some(fault) = fault {
        command.arg("-e").arg(format!("inject={fault}"));
    }
    let output = run(command
        .arg(executable().path())
        .args(arguments)
        .stdin(Stdio::from(std::fs::File::open(source.path()).unwrap())));
    let events = std::fs::read_to_string(trace.path()).unwrap();
    cleanup(&events);
    if fault.is_some() {
        assert!(events.contains("INJECTED"), "fault={fault:?}\n{events}");
    }
    (output, events)
}

#[test]
fn every_observed_allocation_and_io_failure_releases_owners_before_reporting() {
    let old = b"first\nkeep\r\nlast\0\xff";
    let new = b"FIRST\nkeep\r\nLAST\0\x80";
    let before = file(old);
    let after = file(new);
    let patch = diff(old, new, &[]);
    assert_eq!(patch.status.code(), Some(1), "{patch:?}");
    let patch_file = file(&patch.stdout);
    let scenarios = [
        (
            vec![
                OsString::from("diff"),
                before.path().into(),
                after.path().into(),
            ],
            b"".as_slice(),
            1,
            patch.stdout.as_slice(),
        ),
        (
            vec![OsString::from("apply"), patch_file.path().into()],
            old.as_slice(),
            0,
            new.as_slice(),
        ),
        (
            vec![OsString::from("check"), patch_file.path().into()],
            old.as_slice(),
            0,
            b"".as_slice(),
        ),
    ];
    for (arguments, input, status, expected) in scenarios {
        let (baseline, events) = traced(&arguments, input, None);
        success(&baseline, status, expected);
        let allocations = cleanup(&events);
        assert!(
            allocations > 5,
            "the scenario must reach owned diff/patch allocations: {events}"
        );
        for when in 1..=allocations {
            for persistent in ["", "+"] {
                let fault = format!("mmap:error=ENOMEM:when={when}{persistent}");
                failure(
                    &traced(&arguments, input, Some(&fault)).0,
                    4,
                    "allocation-failure",
                );
            }
        }
        for syscall in ["open", "openat", "read", "close"] {
            let count = events
                .lines()
                .filter(|line| line.starts_with(&format!("{syscall}(")))
                .count();
            for when in 1..=count {
                let errored = traced(
                    &arguments,
                    input,
                    Some(&format!("{syscall}:error=EIO:when={when}")),
                )
                .0;
                assert_eq!(
                    errored.status.code(),
                    Some(3),
                    "EIO syscall={syscall} when={when}: {errored:?}"
                );
                failure(&errored, 3, "io-failure");
                let interrupted = traced(
                    &arguments,
                    input,
                    Some(&format!("{syscall}:error=EINTR:when={when}")),
                )
                .0;
                if syscall != "read" {
                    // File open makes one host attempt. Close invalidates its
                    // owner before one attempt; only stream reads retry EINTR.
                    assert_eq!(
                        interrupted.status.code(),
                        Some(3),
                        "EINTR syscall={syscall} when={when}: {interrupted:?}"
                    );
                    failure(&interrupted, 3, "io-failure");
                } else {
                    success(&interrupted, status, expected);
                }
            }
        }
        if events.lines().any(|line| line.starts_with("read(")) {
            failure(
                &traced(&arguments, input, Some("read:error=EAGAIN:when=1")).0,
                3,
                "io-failure",
            );
        }
        let writes: Vec<_> = events
            .lines()
            .filter(|line| line.starts_with("write(1,"))
            .collect();
        let mut offset = 0;
        for (index, line) in writes.iter().enumerate() {
            let when = index + 1;
            let count: usize = line.rsplit(" = ").next().unwrap().parse().unwrap();
            for fault in [
                format!("write:error=EIO:when={when}"),
                format!("write:retval=0:when={when}"),
            ] {
                let output = traced(&arguments, input, Some(&fault)).0;
                assert_eq!(output.status.code(), Some(3), "{output:?}");
                assert_eq!(output.stdout, &expected[..offset], "{output:?}");
                assert!(
                    output.stderr.starts_with(b"text-patch: io-failure"),
                    "{output:?}"
                );
            }
            success(
                &traced(
                    &arguments,
                    input,
                    Some(&format!("write:error=EINTR:when={when}")),
                )
                .0,
                status,
                expected,
            );
            if count > 1 {
                // A fake successful byte is not transferred by strace. The
                // resumed write must start exactly one byte later.
                let mut shortened = expected.to_vec();
                shortened.remove(offset);
                success(
                    &traced(
                        &arguments,
                        input,
                        Some(&format!("write:retval=1:when={when}")),
                    )
                    .0,
                    status,
                    &shortened,
                );
            }
            offset += count;
        }
        assert_eq!(offset, expected.len());
    }
    let (bad_args, events) = traced(
        &args(&["diff", "missing", "missing", "--unknown"]),
        b"",
        None,
    );
    failure(&bad_args, 2, "invalid-arguments");
    assert!(
        !events
            .lines()
            .any(|line| line.starts_with("open(") || line.starts_with("openat(")),
        "{events}"
    );
    let (failed_stderr, _) = traced(&args(&["--unknown"]), b"", Some("write:error=EIO:when=1"));
    assert_eq!(failed_stderr.status.code(), Some(3), "{failed_stderr:?}");
    assert!(
        failed_stderr.stdout.is_empty() && failed_stderr.stderr.is_empty(),
        "{failed_stderr:?}"
    );
    for mode in ["diff", "apply"] {
        let trace = common::TempArtifact::new("laniusc_text_patch", "full_trace", None);
        // The process helper captures stdout, so redirect the native descriptor
        // inside the shell. Run the shell outside strace's native-only trace.
        let script = if mode == "diff" {
            "exec strace -qq -o \"$1\" -e trace=mmap,munmap,open,openat,close,read,write \"$2\" diff \"$3\" \"$4\" >/dev/full"
        } else {
            "exec strace -qq -o \"$1\" -e trace=mmap,munmap,open,openat,close,read,write \"$2\" apply \"$3\" >/dev/full"
        };
        let mut command = Command::new("sh");
        command
            .args(["-c", script, "text-patch"])
            .arg(trace.path())
            .arg(executable().path());
        if mode == "diff" {
            command.arg(before.path()).arg(after.path());
        } else {
            command.arg(patch_file.path());
        }
        let source = file(old);
        let output = run(command.stdin(Stdio::from(std::fs::File::open(source.path()).unwrap())));
        failure(&output, 3, "io-failure");
        cleanup(&std::fs::read_to_string(trace.path()).unwrap());
    }
}

#[test]
fn default_input_line_trace_and_edit_limits_have_native_boundary_coverage() {
    let maximum_input = vec![b'x'; 4 * 1024 * 1024];
    success(&apply("apply", b"", &maximum_input, &[]), 0, &maximum_input);
    let mut too_large = maximum_input;
    too_large.push(b'y');
    failure(&apply("apply", b"", &too_large, &[]), 2, "resource-limit");
    success(
        &apply("apply", b"", &too_large, &["--max-input-bytes=4194305"]),
        0,
        &too_large,
    );
    // Default line capacity is per input and counts a final unterminated line.
    let lines = b"\n".repeat(65_536);
    success(&diff(&lines, &lines, &[]), 0, b"");
    let mut above = lines;
    above.push(b'x');
    failure(&diff(&above, &above, &[]), 2, "resource-limit");
    success(&diff(&above, &above, &["--max-lines=65537"]), 0, b"");
    // A shortest script with many changed lines reaches the default trace cap.
    let before = b"a\n".repeat(800);
    let after = b"b\n".repeat(800);
    failure(&diff(&before, &after, &[]), 2, "resource-limit");
    let expanded = diff(&before, &after, &["--max-trace-cells=2000000"]);
    assert_eq!(expanded.status.code(), Some(1), "{expanded:?}");
    assert!(expanded.stderr.is_empty(), "{expanded:?}");
    success(&apply("apply", &expanded.stdout, &before, &[]), 0, &after);
    // The edit-record cap also bounds retained unchanged records. Raise only
    // the line cap so this boundary is not masked by the default line cap.
    let at_edit_limit = b"\n".repeat(131_072);
    success(
        &diff(&at_edit_limit, &at_edit_limit, &["--max-lines=131073"]),
        0,
        b"",
    );
    let mut above = at_edit_limit;
    above.push(b'\n');
    failure(
        &diff(&above, &above, &["--max-lines=131073"]),
        2,
        "resource-limit",
    );
    success(
        &diff(
            &above,
            &above,
            &["--max-lines=131073", "--max-edits=131073"],
        ),
        0,
        b"",
    );
}

#[test]
fn read_eof_and_short_successes_preserve_input_semantics() {
    let empty_patch = file(b"");
    let arguments = vec![OsString::from("apply"), empty_patch.path().into()];
    let (_, events) = traced(&arguments, b"bc\n", None);
    let stdin_read = events
        .lines()
        .filter(|line| line.starts_with("read("))
        .position(|line| line.starts_with("read(0,"))
        .unwrap()
        + 1;
    success(
        &traced(
            &arguments,
            b"bc\n",
            Some(&format!("read:retval=0:when={stdin_read}")),
        )
        .0,
        0,
        b"",
    );
    // Inject one known byte into a successful short read. strace leaves the
    // source offset unchanged, so the next real read returns the original bc.
    success(
        &traced(
            &arguments,
            b"bc\n",
            Some(&format!(
                "read:retval=1:poke_exit=@arg2=61:when={stdin_read}"
            )),
        )
        .0,
        0,
        b"abc\n",
    );
}

#[test]
fn twenty_thousand_line_sparse_edits_execute_with_compilation_excluded_from_timing() {
    executable();
    let mut old = Vec::new();
    let mut new = Vec::new();
    for index in 0..20_000 {
        old.extend_from_slice(format!("row-{index:05} stable payload\r\n").as_bytes());
        if index % 4001 == 0 {
            new.extend_from_slice(format!("row-{index:05} changed payload\r\n").as_bytes());
        } else if index != 15_005 {
            new.extend_from_slice(format!("row-{index:05} stable payload\r\n").as_bytes());
        }
        if index == 10_010 {
            new.extend_from_slice(b"inserted \xff\0 row\n");
        }
    }
    let before = file(&old);
    let after = file(&new);
    let start = Instant::now();
    let output = invoke(
        &["diff".into(), before.path().into(), after.path().into()],
        b"",
    );
    let diff_elapsed = start.elapsed();
    assert_eq!(output.status.code(), Some(1), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let patch_file = file(&output.stdout);
    let start = Instant::now();
    let patched = invoke(&["apply".into(), patch_file.path().into()], &old);
    let apply_elapsed = start.elapsed();
    success(&patched, 0, &new);
    success(
        &invoke(&["check".into(), patch_file.path().into()], &old),
        0,
        b"",
    );
    gnu_apply(&output.stdout, &old, &new);
    eprintln!("text-patch: 20000 lines, {} old bytes, {} patch bytes; diff {:.3} ms, apply {:.3} ms native elapsed (process setup and I/O included; compilation excluded)",
        old.len(), output.stdout.len(), diff_elapsed.as_secs_f64()*1000.0, apply_elapsed.as_secs_f64()*1000.0);
}
