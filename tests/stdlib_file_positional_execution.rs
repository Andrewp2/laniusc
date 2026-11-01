//! Native explicit-offset I/O, staging, status admission and confirmed prefixes.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    fs,
    io::{Read, Seek, SeekFrom},
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    time::Duration,
};

struct Directory(common::TempArtifact);
impl Directory {
    fn new() -> Self {
        let path = common::TempArtifact::new("laniusc_positional", "directory", None);
        fs::create_dir(path.path()).unwrap();
        Self(path)
    }
    fn path(&self) -> &Path {
        self.0.path()
    }
}
impl Drop for Directory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(self.path());
    }
}

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!(
        "tests/fixtures/stdlib_foundation/file_positional/{name}.lani"
    ));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("native positional I/O", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("positional {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let output = common::TempArtifact::new("laniusc_positional", name, None);
    output.write_bytes(bytes);
    fs::set_permissions(output.path(), fs::Permissions::from_mode(0o700)).unwrap();
    output
}

fn run(
    executable: &common::TempArtifact,
    directory: &Directory,
    mode: Option<u8>,
    injection: Option<&str>,
) -> (Output, String) {
    let trace = common::TempArtifact::new("laniusc_positional", "trace", None);
    let input = common::TempArtifact::new("laniusc_positional", "mode", None);
    input.write_bytes([mode.unwrap_or(0)]);
    let mut command = Command::new("strace");
    command.args(["-qq","-s","64","-o"]).arg(trace.path()).args([
        "-e","trace=openat,pread64,pwrite64,fcntl,lseek,pipe2,close,mmap,mremap,munmap,brk,fsync,fdatasync",
        "-e","signal=none",
    ]);
    if let Some(injection) = injection {
        command.arg("-e").arg(format!("inject={injection}"));
    }
    command.arg(executable.path()).current_dir(directory.path());
    if mode.is_some() {
        command.stdin(fs::File::open(input.path()).unwrap());
    } else {
        command.stdin(Stdio::null());
    }
    let output = common::process_output_with_timeout(
        "native positional I/O lifecycle",
        &mut command,
        Duration::from_secs(5),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    for forbidden in [
        "mmap(",
        "mremap(",
        "munmap(",
        "brk(",
        "fsync(",
        "fdatasync(",
    ] {
        assert!(
            !events.contains(forbidden),
            "allocation/automatic sync forbidden: {events}"
        );
    }
    assert!(output.stderr.is_empty(), "{output:?}\n{events}");
    if let Some(injection) = injection {
        assert_eq!(
            events
                .lines()
                .filter(|line| line.contains("INJECTED"))
                .count(),
            1,
            "unreached/repeated {injection}: {events}"
        );
    } else {
        assert!(!events.contains("INJECTED"), "{events}");
    }
    (output, events)
}

fn calls<'a>(events: &'a str, name: &str) -> Vec<&'a str> {
    let prefix = format!("{name}(");
    events
        .lines()
        .filter(|line| line.starts_with(&prefix))
        .collect()
}
fn positional(events: &str, name: &str) -> Vec<(usize, u64)> {
    calls(events, name)
        .into_iter()
        .map(|line| {
            let (invocation, _) = line
                .rsplit_once('=')
                .unwrap_or_else(|| panic!("missing syscall result: {line}"));
            let invocation = invocation
                .trim_end()
                .strip_suffix(')')
                .unwrap_or_else(|| panic!("missing syscall closing delimiter: {line}"));
            let args = invocation
                .split_once('(')
                .unwrap_or_else(|| panic!("missing syscall opening delimiter: {line}"))
                .1;
            // The trailing count/offset are numeric even when a string buffer
            // contains commas. Read from the right rather than splitting its bytes.
            let mut fields = args.rsplitn(3, ',');
            let offset = fields
                .next()
                .unwrap_or_else(|| panic!("missing position: {line}"))
                .trim()
                .parse()
                .unwrap_or_else(|error| panic!("invalid position ({error}): {line}"));
            let count = fields
                .next()
                .unwrap_or_else(|| panic!("missing count: {line}"))
                .trim()
                .parse()
                .unwrap_or_else(|error| panic!("invalid count ({error}): {line}"));
            (count, offset)
        })
        .collect()
}
#[test]
fn positional_trace_parser_accepts_alignment_and_buffer_punctuation() {
    let events = "pread64(3, \"a,b)c=\", 6, 9)               = 6\npread64(3, 0x7ffe1234, 1024, 4294967311) = -1 EIO (Input/output error) (INJECTED)\npwrite64(3, \"a)b,c=\", 6, 17)    = -1 EAGAIN (Resource temporarily unavailable) (INJECTED)\n";
    assert_eq!(
        positional(events, "pread64"),
        [(6, 9), (1024, 4_294_967_311)]
    );
    assert_eq!(positional(events, "pwrite64"), [(6, 17)]);
}
fn successful_closes(events: &str, count: usize) {
    let closes = calls(events, "close");
    assert_eq!(closes.len(), count, "{events}");
    assert!(closes.iter().all(|line| line.ends_with(" = 0")), "{events}");
}
fn pattern(index: usize) -> u8 {
    ((index * 73 + 19) % 256) as u8
}
fn seed() -> Vec<u8> {
    (0..4096).map(pattern).collect()
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
}

#[test]
fn positional_native_strides_chunks_sparse_offsets_and_duplicate_cursors() {
    let executable = executable("contracts");
    let directory = Directory::new();
    let input = directory.path().join("input");
    fs::write(&input, seed()).unwrap();
    let (output, events) = run(&executable, &directory, None, None);
    checked(&output, 0);
    assert!(output.stdout.is_empty());
    let high = 4_294_967_311;
    assert_eq!(
        positional(&events, "pwrite64"),
        [(1024, 100), (1024, 1124), (5, 2148), (6, 4000), (6, high)],
        "{events}"
    );
    assert_eq!(
        positional(&events, "pread64"),
        [
            (1024, 100),
            (1024, 1124),
            (5, 2148),
            (6, 4000),
            (8, high),
            (1, high + 6)
        ],
        "{events}"
    );
    successful_closes(&events, 2);
    assert_eq!(
        calls(&events, "lseek").len(),
        13,
        "only fixture's explicit cursor observations, no seek/read/restore: {events}"
    );
    assert_eq!(
        calls(&events, "fcntl")
            .iter()
            .filter(|line| line.contains("F_GETFL"))
            .count(),
        11,
        "empty/invalid/closed calls do not check status: {events}"
    );
    let mut expected = seed();
    expected[100..2153].copy_from_slice(&(0..2053).map(pattern).collect::<Vec<_>>());
    let tail = [0, 128, 255, 9, 10, 11];
    expected[4000..4006].copy_from_slice(&tail);
    let mut file = fs::File::open(&input).unwrap();
    assert_eq!(file.metadata().unwrap().len(), high + 6);
    let mut prefix = vec![0; 4096];
    file.read_exact(&mut prefix).unwrap();
    assert_eq!(prefix, expected);
    file.seek(SeekFrom::Start(high - 1)).unwrap();
    let mut actual = [255; 7];
    file.read_exact(&mut actual).unwrap();
    assert_eq!(
        actual,
        [0, 0, 128, 255, 9, 10, 11],
        "sparse hole plus exact high-offset payload"
    );
}

#[test]
fn positional_append_access_and_adopted_pipe_policies_are_explicit() {
    let executable = executable("policy");
    let directory = Directory::new();
    let input = directory.path().join("input");
    fs::write(&input, seed()).unwrap();
    let (output, events) = run(&executable, &directory, None, None);
    checked(&output, 0);
    assert!(output.stdout.is_empty());
    successful_closes(&events, 6);
    assert_eq!(calls(&events, "pipe2").len(), 1, "{events}");
    assert_eq!(
        positional(&events, "pread64"),
        [(2, 0), (2, 2), (2, 0), (2, 0)],
        "{events}"
    );
    assert_eq!(
        positional(&events, "pwrite64"),
        [(2, 2), (2, 0), (2, 4), (2, 0)],
        "append rejection must not pwrite: {events}"
    );
    assert!(
        events.contains("EBADF") && events.contains("ESPIPE"),
        "{events}"
    );
    let mut expected = seed();
    expected[2..6].copy_from_slice(&[44, 45, 44, 45]);
    assert_eq!(fs::read(input).unwrap(), expected);
}

#[test]
fn adopted_direct_io_descriptor_is_rejected_before_positional_calls() {
    let executable = executable("direct");
    let directory = Directory::new();
    let input = directory.path().join("input");
    let expected = seed();
    fs::write(&input, &expected).unwrap();
    let (output, events) = run(&executable, &directory, None, None);
    assert!(output.stdout.is_empty());
    assert!(
        positional(&events, "pread64").is_empty() && positional(&events, "pwrite64").is_empty(),
        "{events}"
    );
    match output.status.code() {
        Some(0) => {
            successful_closes(&events, 1);
            assert_eq!(calls(&events, "fcntl").len(), 2, "{events}");
        }
        Some(77) => {
            successful_closes(&events, 0);
            assert!(
                events.contains("EINVAL") || events.contains("EOPNOTSUPP"),
                "{events}"
            );
            eprintln!(
                "filesystem declined O_DIRECT at open; adopted-direct rejection branch not exercised"
            );
        }
        _ => panic!("{output:?}\n{events}"),
    }
    assert_eq!(fs::read(input).unwrap(), expected);
}

#[test]
fn native_fault_schedules_preserve_staging_progress_positions_and_published_bytes() {
    let executable = executable("fault");
    let directory = Directory::new();
    let input = directory.path().join("input");
    // mode, injection, Error code, confirmed bytes, positional attempts.
    let cases = [
        (0, None, 0, 4, 1),
        (0, Some("pread64:error=EINTR:when=1"), 104, 0, 1),
        (0, Some("pread64:error=EAGAIN:when=1"), 111, 0, 1),
        (0, Some("pread64:error=EIO:when=1"), 105, 0, 1),
        (0, Some("pread64:retval=5:when=1"), 196, 0, 1),
        (0, Some("pread64:retval=0:when=1"), 0, 0, 1),
        (0, Some("fcntl:error=EIO:when=1"), 105, 0, 0),
        (0, Some("fcntl:retval=2147483648:when=1"), 196, 0, 0),
        (1, None, 0, 4, 1),
        (1, Some("pwrite64:error=EINTR:when=1"), 104, 0, 1),
        (1, Some("pwrite64:error=EAGAIN:when=1"), 111, 0, 1),
        (1, Some("pwrite64:error=EIO:when=1"), 105, 0, 1),
        (1, Some("pwrite64:error=ENOSPC:when=1"), 128, 0, 1),
        (1, Some("pwrite64:retval=5:when=1"), 196, 0, 1),
        (1, Some("pwrite64:retval=0:when=1"), 0, 0, 1),
        (2, None, 0, 2050, 3),
        (2, Some("pread64:error=EINTR:when=1"), 0, 2050, 4),
        (2, Some("pread64:error=EAGAIN:when=2"), 111, 1024, 2),
        (2, Some("pread64:error=EIO:when=2"), 105, 1024, 2),
        (2, Some("pread64:retval=1025:when=2"), 196, 1024, 2),
        (2, Some("pread64:retval=0:when=2"), 197, 1024, 2),
        (3, None, 0, 2050, 3),
        (3, Some("pwrite64:error=EINTR:when=1"), 0, 2050, 4),
        (3, Some("pwrite64:error=EAGAIN:when=2"), 111, 1024, 2),
        (3, Some("pwrite64:error=EIO:when=2"), 105, 1024, 2),
        (3, Some("pwrite64:error=ENOSPC:when=2"), 128, 1024, 2),
        (3, Some("pwrite64:retval=1025:when=2"), 196, 1024, 2),
        (3, Some("pwrite64:retval=0:when=2"), 198, 1024, 2),
        (4, None, 199, 1024, 1),
        (5, None, 199, 1024, 1),
    ];
    for (mode, injection, code, completed, attempts) in cases {
        let mut expected = seed();
        fs::write(&input, &expected).unwrap();
        let (output, events) = run(&executable, &directory, Some(mode), injection);
        checked(&output, 0);
        assert_eq!(output.stdout.len(), 8, "{output:?}\n{events}");
        let actual: Vec<i32> = output
            .stdout
            .chunks_exact(4)
            .map(|word| i32::from_le_bytes(word.try_into().unwrap()))
            .collect();
        assert_eq!(
            actual,
            [code, completed],
            "mode={mode} injection={injection:?}\n{events}"
        );
        successful_closes(&events, 1);
        assert_eq!(
            calls(&events, "lseek").len(),
            1,
            "only fixture position query: {events}"
        );
        let name = if mode % 2 == 0 { "pread64" } else { "pwrite64" };
        let transfers = positional(&events, name);
        assert_eq!(transfers.len(), attempts, "{events}");
        let opposite = if mode % 2 == 0 { "pwrite64" } else { "pread64" };
        assert!(calls(&events, opposite).is_empty(), "{events}");
        let mut position = 5;
        for (index, (requested, at)) in transfers.iter().enumerate() {
            assert_eq!(*at, position, "advance only confirmed prefix: {events}");
            let full_count = if mode < 2 { 4 } else { 2050 };
            assert_eq!(
                *requested,
                (full_count - (position - 5) as usize).min(1024),
                "{events}"
            );
            let interrupted = injection.is_some_and(|text| text.contains("EINTR") && index == 0);
            if !interrupted {
                position += *requested as u64;
            }
        }
        if mode % 2 == 1 {
            expected[5..5 + completed as usize]
                .copy_from_slice(&(0..completed as usize).map(pattern).collect::<Vec<_>>());
        }
        assert_eq!(
            fs::read(&input).unwrap(),
            expected,
            "actual filesystem publication mode={mode} injection={injection:?}\n{events}"
        );
    }
    eprintln!("native-positional finite_schedules=30");
}
