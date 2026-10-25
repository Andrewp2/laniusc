//! Streaming SHA-2 stdin application with independent hashlib and syscall evidence.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    ffi::{OsStr, OsString},
    fs,
    os::unix::{ffi::OsStringExt, fs::PermissionsExt},
    path::PathBuf,
    process::{Command, Output, Stdio},
    sync::OnceLock,
};
const MAX_INPUT: usize = 16 * 1_048_576;
const MAX_CALLS: usize = 131_072;
const ALGORITHMS: [&str; 6] = [
    "sha224",
    "sha256",
    "sha384",
    "sha512",
    "sha512-224",
    "sha512-256",
];
fn build_executable() -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/hash_bytes.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: Vec::new(),
    };
    let bytes = common::run_gpu_codegen_with_timeout("hash_bytes application", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("hash_bytes: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_hash_bytes", "executable", None);
    file.write_bytes(bytes); // Existing unchanged strict ELF/jump checker.
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn executable() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(build_executable)
}
fn pattern(length: usize) -> Vec<u8> {
    (0..length)
        .map(|index| ((index * 73 + index / 11) & 255) as u8)
        .collect()
}
fn oracle(algorithm: &str, input: &[u8]) -> Vec<u8> {
    let file = common::TempArtifact::new("laniusc_hash_bytes", "oracle-input", None);
    file.write_bytes(input);
    let output = Command::new("timeout")
        .args([
            "--kill-after=1s",
            "5s",
            "python3",
            "-c",
            r#"import hashlib,sys
h=hashlib.new(sys.argv[1].replace('-', '_'))
with open(sys.argv[2], 'rb') as f:
    while True:
        b=f.read(65536)
        if not b: break
        h.update(b)
sys.stdout.write(h.hexdigest()+'\n')
"#,
            algorithm,
        ])
        .arg(file.path())
        .output()
        .unwrap();
    assert!(output.status.success(), "hashlib {algorithm}: {output:?}");
    assert!(output.stderr.is_empty());
    let expected_length = match algorithm {
        "sha224" | "sha512-224" => 57,
        "sha256" | "sha512-256" => 65,
        "sha384" => 97,
        "sha512" => 129,
        _ => unreachable!(),
    };
    assert_eq!(output.stdout.len(), expected_length);
    assert_eq!(output.stdout.last(), Some(&b'\n'));
    assert!(output.stdout[..expected_length - 1]
        .iter()
        .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(byte)));
    output.stdout
}
fn calls<'a>(events: &'a str, name: &str) -> Vec<&'a str> {
    let prefix = format!("{name}(");
    events
        .lines()
        .filter(|line| line.starts_with(&prefix))
        .collect()
}
fn result<'a>(line: &'a str, name: &str) -> (&'a str, &'a str) {
    let body = line.strip_prefix(name).unwrap().strip_prefix('(').unwrap();
    let (arguments, value) = body
        .rsplit_once('=')
        .unwrap_or_else(|| panic!("missing result: {line}"));
    (
        arguments.trim_end().strip_suffix(')').unwrap(),
        value.trim(),
    )
}
fn request(line: &str, name: &str) -> usize {
    result(line, name)
        .0
        .rsplit_once(',')
        .unwrap()
        .1
        .trim()
        .parse()
        .unwrap()
}
struct Run {
    output: Output,
    events: String,
}
fn run(
    executable: &common::TempArtifact,
    input: &[u8],
    args: &[&OsStr],
    injections: &[&str],
    closed_stdout: bool,
    seconds: &str,
) -> Run {
    let data = common::TempArtifact::new("laniusc_hash_bytes", "stdin", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_hash_bytes", "trace", None);
    let mut command = Command::new("timeout");
    command
        .args(["--kill-after=1s", seconds, "strace", "-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=rt_sigaction,read,write,mmap,mremap,munmap,brk",
            "-e",
            "signal=none",
        ]);
    for injection in injections {
        command.arg("-e").arg(format!("inject={injection}"));
    }
    command
        .arg(executable.path())
        .args(args)
        .stdin(Stdio::from(fs::File::open(data.path()).unwrap()));
    if closed_stdout {
        let (reader, writer) = std::io::pipe().unwrap();
        drop(reader);
        command.stdout(writer);
    }
    let output = command.output().expect("bounded hash_bytes native case");
    let events = fs::read_to_string(trace.path()).unwrap();
    for injection in injections {
        let syscall = injection.split(':').next().unwrap();
        let reached = calls(&events, syscall)
            .into_iter()
            .filter(|line| line.contains("INJECTED"))
            .collect::<Vec<_>>();
        if injection.ends_with('+') {
            assert!(
                !reached.is_empty() && reached.len() <= MAX_CALLS,
                "unreached/unbounded {injection}: {events}"
            );
        } else {
            assert_eq!(reached.len(), 1, "unreached/repeated {injection}: {events}");
        }
        if let Some(tail) = injection.split("error=").nth(1) {
            assert!(
                reached
                    .iter()
                    .all(|line| line.contains(tail.split(':').next().unwrap())),
                "{events}"
            );
        }
        if let Some(tail) = injection.split("retval=").nth(1) {
            assert_eq!(
                result(reached[0], syscall)
                    .1
                    .split_whitespace()
                    .next()
                    .unwrap(),
                tail.split(':').next().unwrap(),
                "{events}"
            );
        }
    }
    if injections.is_empty() {
        assert!(!events.contains("INJECTED"), "{events}");
    }
    for name in ["mmap", "mremap", "munmap", "brk"] {
        assert!(
            calls(&events, name).is_empty(),
            "application allocated: {events}"
        );
    }
    Run { output, events }
}
fn checked(run: &Run, status: i32, stdout: &[u8], signal: Option<bool>) {
    assert_eq!(
        run.output.status.code(),
        Some(status),
        "{:?}\n{}",
        run.output,
        run.events
    );
    assert_eq!(run.output.stdout, stdout, "{}", run.events);
    assert!(
        run.output.stderr.is_empty(),
        "{:?}\n{}",
        run.output,
        run.events
    );
    let actions = calls(&run.events, "rt_sigaction");
    if let Some(success) = signal {
        assert_eq!(actions.len(), 1, "{}", run.events);
        assert!(
            actions[0].contains("SIGPIPE") && actions[0].contains("SIG_IGN"),
            "{}",
            run.events
        );
        if success {
            assert_eq!(result(actions[0], "rt_sigaction").1, "0", "{}", run.events);
        } else {
            assert!(actions[0].contains("EINTR") && actions[0].contains("INJECTED"));
        }
        let action = run
            .events
            .lines()
            .position(|line| line.starts_with("rt_sigaction("))
            .unwrap();
        if let Some(io) = run
            .events
            .lines()
            .position(|line| line.starts_with("read(") || line.starts_with("write("))
        {
            assert!(action < io, "{}", run.events);
        }
    } else {
        assert!(actions.is_empty(), "{}", run.events);
    }
    let reads = calls(&run.events, "read");
    let writes = calls(&run.events, "write");
    assert!(
        reads.len() + writes.len() <= MAX_CALLS,
        "I/O budget exceeded"
    );
    for read in &reads {
        assert!(read.starts_with("read(0,"));
        assert!((1..=1024).contains(&request(read, "read")));
    }
    for write in &writes {
        assert!(write.starts_with("write(1,"));
        assert!((1..=129).contains(&request(write, "write")));
    }
    if status == 0 || !writes.is_empty() {
        assert_eq!(
            result(reads.last().unwrap(), "read").1,
            "0",
            "publication requires actual EOF: {}",
            run.events
        );
        if !writes.is_empty() {
            let eof = run
                .events
                .lines()
                .enumerate()
                .filter_map(|(index, line)| line.starts_with("read(").then_some(index))
                .last()
                .unwrap();
            let first_write = run
                .events
                .lines()
                .position(|line| line.starts_with("write("))
                .unwrap();
            assert!(eof < first_write);
        }
    }
    if status == 2 || signal == Some(false) {
        assert!(reads.is_empty() && writes.is_empty());
    }
}

#[test]
fn hash_bytes_algorithms_vectors_and_io_failures() {
    let executable = executable();
    let mut native_cases = 0usize;
    let mut vectors = vec![Vec::new(), b"abc".to_vec(), (0..=255).collect::<Vec<u8>>()];
    for length in [
        55, 56, 63, 64, 65, 111, 112, 127, 128, 129, 1023, 1024, 1025, 4097,
    ] {
        vectors.push(pattern(length));
    }
    assert_eq!(vectors.len(), 17);
    for algorithm in ALGORITHMS {
        for data in &vectors {
            let expected = oracle(algorithm, data);
            let observed = run(
                &executable,
                data,
                &[OsStr::new(algorithm)],
                &[],
                false,
                "5s",
            );
            native_cases += 1;
            checked(&observed, 0, &expected, Some(true));
        }
    }
    let data = pattern(4097);
    let expected = oracle("sha256", &data);
    let baseline = run(&executable, &data, &[], &[], false, "5s");
    native_cases += 1;
    checked(&baseline, 0, &expected, Some(true));
    let baseline_reads = calls(&baseline.events, "read").len();
    assert_eq!(baseline_reads, 6);
    for argument in [
        "",
        "sha1",
        "SHA256",
        " sha256",
        "sha512/224",
        "sha512-257",
        "sha256x",
        "this-algorithm-name-is-longer-than-ten-bytes",
    ] {
        let observed = run(
            &executable,
            &data,
            &[OsStr::new(argument)],
            &[],
            false,
            "5s",
        );
        native_cases += 1;
        checked(&observed, 2, b"", None);
    }
    let observed = run(
        &executable,
        &data,
        &[OsStr::new("sha256"), OsStr::new("sha512")],
        &[],
        false,
        "5s",
    );
    native_cases += 1;
    checked(&observed, 2, b"", None);
    let raw = OsString::from_vec(vec![255]);
    let observed = run(&executable, &data, &[raw.as_os_str()], &[], false, "5s");
    native_cases += 1;
    checked(&observed, 2, b"", None);
    for (injection, status, reads) in [
        ("read:error=EIO:when=1", 3, 1),
        ("read:error=EIO:when=2", 3, 2),
        ("read:error=EAGAIN:when=1", 3, 1),
        ("read:retval=1025:when=1", 3, 1),
        ("read:error=EINTR:when=1", 0, baseline_reads + 1),
    ] {
        let observed = run(&executable, &data, &[], &[injection], false, "5s");
        native_cases += 1;
        checked(
            &observed,
            status,
            if status == 0 { &expected } else { b"" },
            Some(true),
        );
        assert_eq!(calls(&observed.events, "read").len(), reads);
        if status != 0 {
            assert!(calls(&observed.events, "write").is_empty());
        }
    }
    for (injection, status, output, writes) in [
        ("write:error=EIO:when=1", 3, b"".as_slice(), 1),
        ("write:error=EAGAIN:when=1", 3, b"".as_slice(), 1),
        ("write:retval=0:when=1", 3, b"".as_slice(), 1),
        ("write:retval=66:when=1", 3, b"".as_slice(), 1),
        ("write:error=EINTR:when=1", 0, expected.as_slice(), 2),
        ("write:retval=1:when=1", 0, &expected[1..], 2),
    ] {
        let observed = run(&executable, &data, &[], &[injection], false, "5s");
        native_cases += 1;
        checked(&observed, status, output, Some(true));
        let calls = calls(&observed.events, "write");
        assert_eq!(calls.len(), writes);
        if injection.contains("retval=1:") {
            assert_eq!(request(calls[1], "write"), 64);
        }
    }
    let observed = run(&executable, &data, &[], &[], true, "5s");
    native_cases += 1;
    checked(&observed, 3, b"", Some(true));
    let writes = calls(&observed.events, "write");
    assert_eq!(writes.len(), 1);
    assert!(writes[0].contains("EPIPE") && !writes[0].contains("INJECTED"));
    let observed = run(
        &executable,
        &data,
        &[],
        &["rt_sigaction:error=EINTR:when=1"],
        false,
        "5s",
    );
    native_cases += 1;
    checked(&observed, 3, b"", Some(false));
    assert_eq!(native_cases, 126);
    eprintln!("hash_bytes ordinary: one strict ELF, {native_cases} native cases, all six algorithms, no allocation syscalls");
}

#[test]
fn hash_bytes_global_call_budget_bounds_interrupted_io() {
    let executable = executable();
    let observed = run(
        &executable,
        b"abc",
        &[],
        &["read:error=EINTR:when=1+"],
        false,
        "20s",
    );
    checked(&observed, 7, b"", Some(true));
    assert_eq!(calls(&observed.events, "read").len(), MAX_CALLS);
    assert!(calls(&observed.events, "write").is_empty());
    let observed = run(
        &executable,
        b"abc",
        &[],
        &["write:error=EINTR:when=1+"],
        false,
        "20s",
    );
    checked(&observed, 7, b"", Some(true));
    assert_eq!(calls(&observed.events, "read").len(), 2);
    assert_eq!(calls(&observed.events, "write").len(), MAX_CALLS - 2);
    eprintln!(
        "hash_bytes budget: one strict ELF, 2 native cases reaching the shared131072-call limit"
    );
}

#[test]
fn hash_bytes_exact_input_limit_and_one_byte_excess() {
    let executable = executable();
    let mut data = pattern(MAX_INPUT);
    let expected = oracle("sha256", &data);
    let observed = run(&executable, &data, &[], &[], false, "20s");
    checked(&observed, 0, &expected, Some(true));
    let reads = calls(&observed.events, "read");
    assert_eq!(reads.len(), MAX_INPUT / 1024 + 1);
    assert_eq!(request(reads.last().unwrap(), "read"), 1);
    assert_eq!(result(reads.last().unwrap(), "read").1, "0");
    data.push(165);
    let observed = run(&executable, &data, &[], &[], false, "20s");
    checked(&observed, 7, b"", Some(true));
    let reads = calls(&observed.events, "read");
    assert_eq!(reads.len(), MAX_INPUT / 1024 + 1);
    assert_eq!(request(reads.last().unwrap(), "read"), 1);
    assert_eq!(result(reads.last().unwrap(), "read").1, "1");
    assert!(calls(&observed.events, "write").is_empty());
    eprintln!("hash_bytes bound: one strict ELF, 2 native cases at16MiB and16MiB+1, actual one-byte EOF probe");
}
fn scale(algorithm: &str) {
    let executable = executable();
    let data = pattern(1_048_576);
    let expected = oracle(algorithm, &data);
    let started = std::time::Instant::now();
    let observed = run(
        &executable,
        &data,
        &[OsStr::new(algorithm)],
        &[],
        false,
        "20s",
    );
    let elapsed = started.elapsed();
    checked(&observed, 0, &expected, Some(true));
    assert_eq!(calls(&observed.events, "read").len(), 1025);
    eprintln!("hash_bytes scale {algorithm}: one strict ELF, 1 native case, exact1MiB against hashlib; observed case wall {:.3} ms (run(): input-file setup, strace, process startup and trace parsing; not isolated hash throughput)", elapsed.as_secs_f64() * 1000.0);
}
#[test]
fn hash_bytes_one_mebibyte_sha224() {
    scale("sha224");
}
#[test]
fn hash_bytes_one_mebibyte_sha256() {
    scale("sha256");
}
#[test]
fn hash_bytes_one_mebibyte_sha384() {
    scale("sha384");
}
#[test]
fn hash_bytes_one_mebibyte_sha512() {
    scale("sha512");
}
#[test]
fn hash_bytes_one_mebibyte_sha512_224() {
    scale("sha512-224");
}
#[test]
fn hash_bytes_one_mebibyte_sha512_256() {
    scale("sha512-256");
}
