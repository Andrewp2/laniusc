#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    ffi::OsString,
    os::unix::{ffi::OsStringExt, fs::PermissionsExt},
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
    let exe = common::TempArtifact::new("laniusc_cli", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("CLI", command)
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn rows(output: &[u8]) -> Vec<Vec<i32>> {
    std::str::from_utf8(output)
        .unwrap()
        .lines()
        .map(|line| {
            line.split_ascii_whitespace()
                .map(|n| n.parse().unwrap())
                .collect()
        })
        .collect()
}
fn option(
    id: i32,
    argument: usize,
    offset: usize,
    value: Option<(usize, usize, &[u8])>,
) -> Vec<i32> {
    let mut row = vec![
        1,
        id,
        argument as i32,
        offset as i32,
        i32::from(value.is_some()),
    ];
    if let Some((arg, at, bytes)) = value {
        row.extend([arg as i32, at as i32, bytes.len() as i32]);
        row.extend(bytes.iter().map(|&b| i32::from(b)));
    }
    row
}
fn operand(argument: usize, bytes: &[u8]) -> Vec<i32> {
    let mut row = vec![2, argument as i32, 0, bytes.len() as i32];
    row.extend(bytes.iter().map(|&b| i32::from(b)));
    row
}
fn invoke(exe: &common::TempArtifact, first: bool, args: &[Vec<u8>]) -> Vec<Vec<i32>> {
    let output = run(Command::new(exe.path())
        .arg(if first { "first" } else { "mixed" })
        .args(args.iter().cloned().map(OsString::from_vec)));
    checked(&output, 0);
    rows(&output.stdout)
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
fn schema_validation_and_borrowed_parser_execute_without_allocation() {
    let exe = executable("tests/fixtures/extended/cli_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_cli", "schema_trace", None);
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

#[test]
fn host_snapshots_preserve_raw_bytes_check_limits_and_release_failed_allocations() {
    let exe = executable("tests/fixtures/stdlib_host/args_snapshot.lani");
    let trace = common::TempArtifact::new("laniusc_cli", "snapshot_trace", None);
    for when in 0..=2 {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if when > 0 {
            command
                .arg("-e")
                .arg(format!("inject=mmap:error=ENOMEM:when={when}+"));
        }
        let output = run(command
            .arg(exe.path())
            .arg(OsString::from_vec(vec![255, b'a']))
            .args(["", "b"]));
        checked(&output, 0);
        assert!(output.stdout.is_empty());
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert_eq!(freed(&events), if when == 0 { 2 } else { when - 1 });
        assert_eq!(events.contains("INJECTED"), when > 0);
    }
}

#[test]
fn empty_arguments_and_executable_inclusion_have_independent_storage() {
    let exe = executable("tests/fixtures/stdlib_host/args_snapshot_empty.lani");
    let trace = common::TempArtifact::new("laniusc_cli", "empty_snapshot_trace", None);
    for when in 0..=3 {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if when > 0 {
            command
                .arg("-e")
                .arg(format!("inject=mmap:error=ENOMEM:when={when}+"));
        }
        let output = run(command.arg(exe.path()).args(["", ""]));
        checked(&output, 0);
        assert!(output.stdout.is_empty());
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert_eq!(freed(&events), if when == 0 { 3 } else { when - 1 });
        assert_eq!(events.contains("INJECTED"), when > 0);
    }
}

#[test]
fn large_argument_lists_parse_without_allocating_after_snapshot() {
    let exe = executable("tests/fixtures/extended/cli_workload.lani");
    for count in [4096, 32768] {
        let trace = common::TempArtifact::new("laniusc_cli", "workload_trace", None);
        let output = common::process_output_with_timeout(
            "CLI large list",
            Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args([
                    "-e",
                    "trace=mmap,munmap",
                    "-e",
                    "inject=mmap:error=ENOMEM:when=3+",
                ])
                .arg(exe.path())
                .args(std::iter::repeat("-ab").take(count)),
            std::time::Duration::from_secs(5),
        );
        checked(&output, 0);
        assert_eq!(output.stdout, format!("{}\n", count * 2).as_bytes());
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(!events.contains("INJECTED"));
        assert_eq!(freed(&events), 2);
    }
}

#[test]
fn option_spellings_and_error_locations_follow_the_contract() {
    let exe = executable("tests/fixtures/extended/cli_input.lani");
    let cases: Vec<(Vec<&[u8]>, Vec<Vec<i32>>)> = vec![
        (vec![], vec![]),
        (
            vec![b"-", b"", b"--", b"--alpha", b"-b"],
            vec![
                operand(0, b"-"),
                operand(1, b""),
                operand(3, b"--alpha"),
                operand(4, b"-b"),
            ],
        ),
        (
            vec![b"-abo-1", b"--color=", b"--long-only", b"--", b"-s"],
            vec![
                option(10, 0, 1, None),
                option(20, 0, 2, None),
                option(30, 0, 3, Some((0, 4, b"-1"))),
                option(40, 1, 2, Some((1, 8, b""))),
                option(50, 2, 2, Some((3, 0, b"--"))),
                option(60, 4, 1, None),
            ],
        ),
        (
            vec![b"-c", b"blue", b"--output=", b"-o", b"", b"-c=red"],
            vec![
                option(40, 0, 1, None),
                operand(1, b"blue"),
                option(30, 2, 2, Some((2, 9, b""))),
                option(30, 3, 1, Some((4, 0, b""))),
                option(40, 5, 1, Some((5, 2, b"=red"))),
            ],
        ),
        (vec![b"--alpha=1"], vec![vec![0, 5, 0, 7]]),
        (vec![b"--output"], vec![vec![0, 4, 0, 2]]),
        (
            vec![b"-abo"],
            vec![
                option(10, 0, 1, None),
                option(20, 0, 2, None),
                vec![0, 4, 0, 3],
            ],
        ),
        (vec![b"--al"], vec![vec![0, 3, 0, 2]]),
        (vec![b"--=bad"], vec![vec![0, 3, 0, 2]]),
        (vec![b"-az"], vec![option(10, 0, 1, None), vec![0, 3, 0, 2]]),
        (vec![b"-\xff"], vec![vec![0, 3, 0, 1]]),
        (vec![b"--\xff"], vec![vec![0, 3, 0, 2]]),
        (
            vec![b"-o", b"\xff\xfe"],
            vec![option(30, 0, 1, Some((1, 0, b"\xff\xfe")))],
        ),
        (vec![b"-1"], vec![vec![0, 3, 0, 1]]),
    ];
    for (case, (args, expected)) in cases.into_iter().enumerate() {
        let args: Vec<Vec<u8>> = args.into_iter().map(Vec::from).collect();
        assert_eq!(invoke(&exe, false, &args), expected, "case={case}");
    }
    let args = [
        b"-a".to_vec(),
        b"file".to_vec(),
        b"--".to_vec(),
        b"-b".to_vec(),
    ];
    assert_eq!(
        invoke(&exe, true, &args),
        vec![
            option(10, 0, 1, None),
            operand(1, b"file"),
            operand(2, b"--"),
            operand(3, b"-b")
        ]
    );
    assert_eq!(
        invoke(&exe, false, &args),
        vec![
            option(10, 0, 1, None),
            operand(1, b"file"),
            operand(3, b"-b")
        ]
    );
}

#[test]
fn generated_semantic_events_survive_different_valid_spellings() {
    let exe = executable("tests/fixtures/extended/cli_input.lani");
    let values: [&[u8]; 8] = [
        b"",
        b"abc",
        b"-negative",
        b"--",
        b"a=b",
        b"two words",
        "é😀".as_bytes(),
        b"\xff\xfe",
    ];
    let mut seed = 0xc11_2026_u32;
    let mut random = || {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        seed
    };
    let mut coverage = [0; 10];
    for case in 0..96 {
        let mut args = Vec::<Vec<u8>>::new();
        let mut expected = Vec::new();
        for step in 0..48 {
            let spelling = ((random() >> 16) % 10) as usize;
            coverage[spelling] += 1;
            let value = values[((random() >> 16) as usize) % values.len()];
            let at = args.len();
            match spelling {
                0 => {
                    args.push(b"-absa".to_vec());
                    for (id, offset) in [(10, 1), (20, 2), (60, 3), (10, 4)] {
                        expected.push(option(id, at, offset, None));
                    }
                }
                1 => {
                    args.push(b"--alpha".to_vec());
                    expected.push(option(10, at, 2, None));
                }
                2 => {
                    args.push(b"--output".to_vec());
                    args.push(value.to_vec());
                    expected.push(option(30, at, 2, Some((at + 1, 0, value))));
                }
                3 => {
                    let mut token = b"--output=".to_vec();
                    token.extend(value);
                    args.push(token);
                    expected.push(option(30, at, 2, Some((at, 9, value))));
                }
                4 => {
                    args.push(b"-bo".to_vec());
                    args.push(value.to_vec());
                    expected.push(option(20, at, 1, None));
                    expected.push(option(30, at, 2, Some((at + 1, 0, value))));
                }
                5 => {
                    let mut token = b"-o".to_vec();
                    token.extend(b"attached");
                    token.extend(value);
                    args.push(token);
                    let attached = &args[at][2..];
                    expected.push(option(30, at, 1, Some((at, 2, attached))));
                }
                6 => {
                    let mut token = b"--color=".to_vec();
                    token.extend(value);
                    args.push(token);
                    expected.push(option(40, at, 2, Some((at, 8, value))));
                }
                7 => {
                    args.push(b"-c".to_vec());
                    expected.push(option(40, at, 1, None));
                }
                8 => {
                    args.push(b"--long-only".to_vec());
                    args.push(value.to_vec());
                    expected.push(option(50, at, 2, Some((at + 1, 0, value))));
                }
                9 => {
                    let mut token = b"operand:".to_vec();
                    token.extend(value);
                    expected.push(operand(at, &token));
                    args.push(token);
                }
                _ => unreachable!(),
            }
            if step == 47 {
                args.push(b"--".to_vec());
                for value in values {
                    expected.push(operand(args.len(), value));
                    args.push(value.to_vec());
                }
            }
        }
        assert_eq!(
            invoke(&exe, false, &args),
            expected,
            "seed=0xc112026 case={case}"
        );
    }
    assert!(coverage.into_iter().all(|n| n > 100));
}

// Table-driven reference, independent of the library's bit-at-a-time update.
fn crc32(input: &[u8]) -> u32 {
    let table: [u32; 256] = std::array::from_fn(|value| {
        (0..8).fold(value as u32, |crc, _| {
            if crc & 1 != 0 {
                (crc >> 1) ^ 0xedb88320
            } else {
                crc >> 1
            }
        })
    });
    !input.iter().fold(u32::MAX, |crc, &byte| {
        table[((crc as u8) ^ byte) as usize] ^ (crc >> 8)
    })
}

#[test]
fn checksum_program_executes_streaming_files_raw_paths_options_and_limits() {
    let exe = executable("sample_programs/checksum.lani");
    let input = common::TempArtifact::new("laniusc_cli", "checksum_input", None);
    let invoke = |args: &[OsString], bytes: &[u8]| {
        input.write_bytes(bytes);
        run(Command::new(exe.path())
            .args(args)
            .stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )))
    };
    assert_eq!(crc32(b"123456789"), 0xcbf43926);
    for length in [0, 1, 9, 255, 4095, 4096, 4097, 65536] {
        let bytes: Vec<u8> = (0..length).map(|i| ((i * 37) ^ (i / 256)) as u8).collect();
        for decimal in [false, true] {
            let mut args: Vec<OsString> = vec![format!("--limit={length}").into()];
            if decimal {
                args.push("-d".into());
            }
            let output = invoke(&args, &bytes);
            checked(&output, 0);
            let expected = if decimal {
                format!("{}\n", crc32(&bytes))
            } else {
                format!("{:08x}\n", crc32(&bytes))
            };
            assert_eq!(output.stdout, expected.as_bytes());
        }
        if length > 0 {
            let output = invoke(&[format!("-n{}", length - 1).into()], &bytes);
            checked(&output, 2);
            assert!(output.stdout.is_empty());
        }
    }
    let output = invoke(&[], b"123456789");
    checked(&output, 0);
    assert_eq!(output.stdout, b"cbf43926\n");
    let output = invoke(&["--limit=18446744073709551615".into()], b"123456789");
    checked(&output, 0);
    assert_eq!(output.stdout, b"cbf43926\n");
    let output = invoke(
        &[
            "-n1".into(),
            "--limit=9".into(),
            "-dd".into(),
            "-".into(),
            "-".into(),
        ],
        b"123456789",
    );
    checked(&output, 0);
    assert_eq!(output.stdout, b"3421780262\n0\n");
    for args in [
        vec!["--unknown"],
        vec!["--limit"],
        vec!["--limit="],
        vec!["-n-1"],
        vec!["-n18446744073709551616"],
        vec!["-d=yes"],
        vec!["--help", "--bad"],
        vec!["--limit=1.0"],
    ] {
        let output = invoke(
            &args.iter().map(OsString::from).collect::<Vec<_>>(),
            b"123456789",
        );
        checked(&output, 2);
        assert!(output.stdout.is_empty(), "{args:?}");
    }
    let output = invoke(&["--help".into()], b"ignored");
    checked(&output, 0);
    assert_eq!(
        output.stdout,
        b"Usage: checksum [-d|-x] [-n BYTES] [-c CONFIG] [--] [FILE ...]\n"
    );
    let output = invoke(
        &["--limit".into(), OsString::from_vec(vec![255])],
        b"ignored",
    );
    checked(&output, 2);
    assert!(output.stdout.is_empty());
    let directory = common::TempArtifact::new("laniusc_cli", "checksum_files", None);
    std::fs::create_dir(directory.path()).unwrap();
    let raw_name = OsString::from_vec(vec![b'-', 255, b'a']);
    let path = directory.path().join(&raw_name);
    std::fs::write(&path, b"123456789").unwrap();
    let output = run(Command::new(exe.path())
        .current_dir(directory.path())
        .arg("--decimal")
        .arg("--")
        .arg(&raw_name));
    checked(&output, 0);
    assert_eq!(output.stdout, b"3421780262\n");
    input.write_bytes(b"abc");
    let output = run(Command::new(exe.path())
        .arg(input.path())
        .arg("--decimal")
        .arg(&path));
    checked(&output, 0);
    assert_eq!(
        output.stdout,
        format!("{}\n3421780262\n", crc32(b"abc")).as_bytes()
    );
    let output = run(Command::new(exe.path()).arg(directory.path().join("missing")));
    checked(&output, 3);
    assert!(output.stdout.is_empty());
    // The invalid option after a missing path must be diagnosed before any open.
    let output = run(Command::new(exe.path())
        .arg(directory.path().join("missing"))
        .arg("--bad"));
    checked(&output, 2);
    assert!(output.stdout.is_empty());
    std::fs::remove_dir_all(directory.path()).unwrap();
}

#[test]
fn checksum_failures_close_files_free_snapshots_and_preserve_output_prefixes() {
    let exe = executable("sample_programs/checksum.lani");
    let input = common::TempArtifact::new("laniusc_cli", "checksum_fault_input", None);
    let bytes: Vec<u8> = (0..8193).map(|i| (i * 41) as u8).collect();
    input.write_bytes(&bytes);
    let expected = format!("{:08x}\n", crc32(&bytes)).into_bytes();
    let trace = common::TempArtifact::new("laniusc_cli", "checksum_fault_trace", None);
    let execute = |injection: Option<String>, status: i32| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,open,openat,close,read,write"]);
        if let Some(ref injection) = injection {
            command.arg("-e").arg(format!("inject={injection}"));
        }
        let output = run(command.arg(exe.path()).arg(input.path()));
        checked(&output, status);
        if status == 0 {
            assert_eq!(output.stdout, expected);
        } else {
            assert!(expected.starts_with(&output.stdout));
        }
        let events = std::fs::read_to_string(trace.path()).unwrap();
        freed(&events);
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
        if injection.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        events
    };
    let baseline = execute(None, 0);
    assert_eq!(
        baseline.lines().filter(|l| l.starts_with("mmap(")).count(),
        2
    );
    for when in 1..=2 {
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
    for call in ["read", "write"] {
        execute(Some(format!("{call}:error=EINTR:when=1")), 0);
    }
    execute(Some("close:error=EINTR:when=1".into()), 3);
    execute(Some("write:retval=0:when=1".into()), 3);
    // No argument snapshot allocations and no input-sized allocations on stdin.
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap",
            "-e",
            "inject=mmap:error=ENOMEM:when=1+",
        ])
        .arg(exe.path())
        .stdin(std::process::Stdio::from(
            std::fs::File::open(input.path()).unwrap(),
        )));
    checked(&output, 0);
    assert_eq!(output.stdout, expected);
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}
