#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    ffi::OsString,
    os::unix::{ffi::OsStringExt, fs::PermissionsExt},
    process::{Command, Output, Stdio},
    time::Duration,
};

fn executable() -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/path_filter.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("path-filter", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("path-filter: {e}"));
    let exe = common::TempArtifact::new("laniusc_path_filter", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("path-filter", command, Duration::from_secs(5))
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn input(bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_path_filter", "input", None);
    file.write_bytes(bytes);
    file
}
fn invoke(exe: &common::TempArtifact, args: &[&str], bytes: &[u8]) -> Output {
    let file = input(bytes);
    run(Command::new(exe.path())
        .args(args)
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())))
}
fn nul_records(records: &[Vec<u8>]) -> Vec<u8> {
    records
        .iter()
        .flat_map(|r| r.iter().copied().chain([0]))
        .collect()
}

#[test]
fn path_filter_executes_recursive_byte_paths_options_and_eof_records() {
    let exe = executable();
    let bytes = b"a.txt\0a/b.txt\0a/b.rs\0.hidden/x.txt\0a/.hidden.txt\0\xff.txt\0a/new\nline.txt\0tail.txt";
    let output = invoke(&exe, &["**/*.txt"], bytes);
    checked(&output, 0);
    assert_eq!(
        output.stdout,
        b"a.txt\0a/b.txt\0\xff.txt\0a/new\nline.txt\0tail.txt\0"
    );
    let output = invoke(&exe, &["--no-globstar", "**/*.txt"], bytes);
    checked(&output, 0);
    assert_eq!(output.stdout, b"a/b.txt\0a/new\nline.txt\0");
    let output = invoke(&exe, &["-ai", "**/*.TXT"], bytes);
    checked(&output, 0);
    assert_eq!(
        output.stdout,
        b"a.txt\0a/b.txt\0.hidden/x.txt\0a/.hidden.txt\0\xff.txt\0a/new\nline.txt\0tail.txt\0"
    );
    for (bytes, expected) in [
        (b"".as_slice(), b"".as_slice()),
        (b"\0".as_slice(), b"\0".as_slice()),
        (b"\0x\0\0".as_slice(), b"\0\0".as_slice()),
        (b"x".as_slice(), b"".as_slice()),
    ] {
        let output = invoke(&exe, &[""], bytes);
        checked(&output, 0);
        assert_eq!(output.stdout, expected);
    }
    let output = invoke(&exe, &["--", "-x*"], b"-xyz\0x\0");
    checked(&output, 0);
    assert_eq!(output.stdout, b"-xyz\0");
    let file = input(b"\xffx\0x\0");
    let output = run(Command::new(exe.path())
        .arg(OsString::from_vec(vec![255, b'*']))
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
    checked(&output, 0);
    assert_eq!(output.stdout, b"\xffx\0");

    // Each record is independent; delimiter, payload and UTF-8 boundaries may
    // fall anywhere inside the descriptor adapter's 1024-byte reads.
    let records: Vec<Vec<u8>> = [0, 1, 1022, 1023, 1024, 1025, 4095, 4096, 65536]
        .into_iter()
        .map(|n| (0..n).map(|i| ((i * 37) % 255 + 1) as u8).collect())
        .collect();
    let data = nul_records(&records);
    let output = invoke(&exe, &["--all", "**"], &data);
    checked(&output, 0);
    assert_eq!(output.stdout, data);
    let without_final = &data[..data.len() - 1];
    let output = invoke(&exe, &["--all", "**"], without_final);
    checked(&output, 0);
    assert_eq!(output.stdout, data);
}

#[test]
fn path_filter_validates_before_output_and_enforces_record_and_work_limits() {
    let exe = executable();
    for args in [
        vec![],
        vec!["a", "b"],
        vec!["--bad", "*"],
        vec!["--all=yes", "*"],
        vec!["--max-path-bytes"],
        vec!["--max-path-bytes=-1", "*"],
        vec!["--max-path-bytes=1048577", "*"],
        vec!["--max-work=18446744073709551616", "*"],
        vec!["--max-work=+1", "*"],
        vec!["["],
        vec!["a\\"],
        vec!["--help", "--bad"],
    ] {
        let output = invoke(&exe, &args, b"a\0");
        checked(&output, 2);
        assert!(output.stdout.is_empty(), "{args:?}");
    }
    let output = invoke(&exe, &["--help"], b"");
    checked(&output, 0);
    assert_eq!(output.stdout,b"Usage: path-filter [--all] [--ignore-case] [--no-globstar] [--max-path-bytes N] [--max-work N] [--] PATTERN\n");
    let output = invoke(&exe, &["--max-path-bytes=0", "*"], b"\0x");
    checked(&output, 2);
    assert_eq!(output.stdout, b"\0");
    let output = invoke(&exe, &["--max-path-bytes=3", "*"], b"abc\0abcd\0");
    checked(&output, 2);
    assert_eq!(output.stdout, b"abc\0");
    // One token and three input bytes require exactly 17 loop slots.
    let output = invoke(&exe, &["--max-work=17", "*"], b"abc\0");
    checked(&output, 0);
    assert_eq!(output.stdout, b"abc\0");
    let output = invoke(&exe, &["--max-work=16", "*"], b"abc\0");
    checked(&output, 2);
    assert!(output.stdout.is_empty());
    let output = invoke(&exe, &["--max-work=0", "*"], b"");
    checked(&output, 0);
    assert!(output.stdout.is_empty());
    // Argument snapshots and compilation are bounded separately from records.
    let long = "a".repeat(16385);
    let output = invoke(&exe, &[&long], b"");
    checked(&output, 2);
    assert!(output.stdout.is_empty());
    let tokens = "a".repeat(4097);
    let output = invoke(&exe, &[&tokens], b"");
    checked(&output, 2);
    assert!(output.stdout.is_empty());
    let args = vec!["-a"; 33];
    let output = invoke(&exe, &args, b"");
    checked(&output, 2);
    assert!(output.stdout.is_empty());
}

fn allocation_count_and_no_leaks(events: &str) -> usize {
    let mut owners = std::collections::BTreeSet::new();
    let mut allocations = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let value = line.rsplit(" = ").next().unwrap();
            if value.starts_with("0x") {
                assert!(
                    owners.insert(value.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                allocations += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && owners.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(owners.is_empty(), "leaked owners: {events}");
    allocations
}
#[test]
fn path_filter_releases_owners_on_every_allocation_and_io_failure() {
    let exe = executable();
    let trace = common::TempArtifact::new("laniusc_path_filter", "trace", None);
    let data = [vec![b'x'; 2500], vec![0], b"tail\0".to_vec()].concat();
    let file = input(&data);
    let execute = |injection: Option<&str>, status| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write"]);
        if let Some(injection) = injection {
            command.arg("-e").arg(format!("inject={injection}"));
        }
        let output = run(command
            .arg(exe.path())
            .arg("*")
            .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
        checked(&output, status);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        let allocations = allocation_count_and_no_leaks(&events);
        if injection.is_some_and(|s| !s.ends_with('+')) {
            assert!(events.contains("INJECTED"), "{events}");
        }
        (output, allocations, events)
    };
    let (output, allocations, events) = execute(None, 0);
    assert_eq!(output.stdout, data);
    assert!(allocations >= 5, "{events}");
    for when in 1..=allocations {
        execute(Some(&format!("mmap:error=ENOMEM:when={when}")), 4);
    }
    let reads = events.lines().filter(|s| s.starts_with("read(")).count();
    let writes = events.lines().filter(|s| s.starts_with("write(")).count();
    for when in 1..=reads {
        execute(Some(&format!("read:error=EIO:when={when}")), 3);
    }
    for when in 1..=writes {
        execute(Some(&format!("write:error=EIO:when={when}")), 3);
    }
    for injection in ["read:error=EINTR:when=1", "write:error=EINTR:when=1"] {
        let (output, _, _) = execute(Some(injection), 0);
        assert_eq!(output.stdout, data);
    }
    for injection in [
        "read:error=EAGAIN:when=1",
        "write:error=EAGAIN:when=1",
        "write:retval=0:when=1",
    ] {
        execute(Some(injection), 3);
    }
    // A reused record buffer stops allocating after its longest record. Deny
    // every later allocation while processing many records of that size.
    let repeated = vec![data.clone(); 64].concat();
    file.write_bytes(&repeated);
    let (output, actual, events) = execute(
        Some(&format!("mmap:error=ENOMEM:when={}+", allocations + 1)),
        0,
    );
    assert_eq!(output.stdout, repeated);
    assert_eq!(actual, allocations);
    assert!(!events.contains("INJECTED"), "{events}");
}
