//! Native whole-file advisory locks, owner lifetime and one-attempt failures.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    time::Duration,
};

struct Directory(common::TempArtifact);
impl Directory {
    fn new() -> Self {
        let path = common::TempArtifact::new("laniusc_file_lock", "directory", None);
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
        "tests/fixtures/stdlib_foundation/file_lock/{name}.lani"
    ));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("native file locks", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("file lock {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let output = common::TempArtifact::new("laniusc_file_lock", name, None);
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
    let trace = common::TempArtifact::new("laniusc_file_lock", "trace", None);
    let input = common::TempArtifact::new("laniusc_file_lock", "mode", None);
    input.write_bytes([mode.unwrap_or(0)]);
    let mut command = Command::new("strace");
    command.args(["-qq", "-n", "-s", "64", "-o"]).arg(trace.path()).args([
        "-e", "trace=openat,flock,fcntl,lseek,read,write,close,mmap,mremap,munmap,brk,fsync,fdatasync,sync,syncfs",
        "-e", "signal=none",
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
        "file lock native lifecycle",
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
        "sync(",
        "syncfs(",
    ] {
        assert!(
            !events.contains(forbidden),
            "allocation/hidden synchronization: {events}"
        );
    }
    common::assert_command_success("native file lock fixture", &output);
    let large_result_injection = matches!(
        injection,
        Some("flock:retval=4294967296:when=1" | "flock:retval=4294967296:when=2")
    );
    let compat_warning =
        b"strace: Injected return value 4294967296 will be clipped to 0 in compat personality\n";
    assert!(
        output.stderr.is_empty()
            || (large_result_injection && output.stderr.as_slice() == compat_warning),
        "unexpected tool stderr: {output:?}\n{events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.contains("INJECTED"))
            .count(),
        usize::from(injection.is_some()),
        "unreached/repeated injection={injection:?}\n{events}"
    );
    (output, events)
}

#[derive(Debug)]
struct Call<'a> {
    number: i32,
    text: &'a str,
}
fn calls<'a>(events: &'a str, name: &str) -> Vec<Call<'a>> {
    let prefix = format!("{name}(");
    events
        .lines()
        .filter_map(|line| {
            let (number, text) = line.trim_start().strip_prefix('[')?.split_once(']')?;
            let text = text.trim_start();
            if !text.starts_with(&prefix) {
                return None;
            }
            Some(Call {
                number: number
                    .trim()
                    .parse()
                    .unwrap_or_else(|error| panic!("syscall number {error}: {line}")),
                text,
            })
        })
        .collect()
}
fn returned(call: &Call<'_>) -> i64 {
    call.text
        .rsplit_once('=')
        .unwrap()
        .1
        .split_whitespace()
        .next()
        .unwrap()
        .parse()
        .unwrap_or_else(|error| panic!("syscall result {error}: {call:?}"))
}
fn fd_argument(call: &Call<'_>) -> i64 {
    call.text
        .split_once('(')
        .unwrap()
        .1
        .split_once(',')
        .unwrap()
        .0
        .trim()
        .parse()
        .unwrap()
}
fn lock_flags(call: &Call<'_>) -> i32 {
    assert_eq!(call.number, 73, "flock must be syscall 73: {call:?}");
    let flags = call
        .text
        .split_once(',')
        .unwrap()
        .1
        .split_once(')')
        .unwrap()
        .0
        .trim();
    flags.split('|').fold(0, |value, flag| {
        value
            | match flag.trim() {
                "LOCK_SH" => 1,
                "LOCK_EX" => 2,
                "LOCK_NB" => 4,
                "LOCK_UN" => 8,
                other => panic!("unexpected lock flag {other}: {call:?}"),
            }
    })
}
fn successful_closes(events: &str, expected: &[i64]) {
    let closes = calls(events, "close");
    assert_eq!(
        closes.len(),
        expected.len(),
        "only explicit live-owner closes: {events}"
    );
    for (call, fd) in closes.iter().zip(expected) {
        assert_eq!(call.number, 3, "{call:?}");
        let actual: i64 = call
            .text
            .split_once('(')
            .unwrap()
            .1
            .split_once(')')
            .unwrap()
            .0
            .trim()
            .parse()
            .unwrap();
        assert_eq!(actual, *fd, "{events}");
        assert_eq!(returned(call), 0, "{events}");
    }
}
fn seed() -> Vec<u8> {
    (0..128)
        .map(|index| ((index * 73 + 19) % 256) as u8)
        .collect()
}
fn unchanged_and_released(directory: &Directory, expected: &[u8]) {
    let path = directory.path().join("input");
    assert_eq!(
        fs::read(&path).unwrap(),
        expected,
        "locks do not change file bytes or length"
    );
    let output = common::process_output_with_timeout(
        "independent host flock verifies last-close release",
        Command::new("flock")
            .args(["--exclusive", "--nonblock"])
            .arg(path)
            .arg("true"),
        Duration::from_secs(5),
    );
    common::assert_command_success("host flock after Lanius owner cleanup", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn file_locks_obey_independent_open_compatibility_and_duplicate_lifetime() {
    let executable = executable("contracts");
    let directory = Directory::new();
    let expected = seed();
    fs::write(directory.path().join("input"), &expected).unwrap();
    let (output, events) = run(&executable, &directory, None, None);
    assert!(output.stdout.is_empty(), "{output:?}");
    let opens = calls(&events, "openat");
    assert_eq!(opens.len(), 5, "{events}");
    assert!(
        opens.iter().all(|call| call.number == 257
            && call.text.contains("\"input\"")
            && returned(call) >= 0),
        "{events}"
    );
    let [a, b, c, owner, competitor]: [i64; 5] = opens
        .iter()
        .map(returned)
        .collect::<Vec<_>>()
        .try_into()
        .unwrap();
    assert!(a != b && a != c && b != c && owner != competitor);
    let duplications: Vec<_> = calls(&events, "fcntl")
        .into_iter()
        .filter(|call| call.text.contains("F_DUPFD_CLOEXEC"))
        .collect();
    assert_eq!(duplications.len(), 1, "{events}");
    assert_eq!(duplications[0].number, 72);
    assert_eq!(fd_argument(&duplications[0]), owner);
    let duplicate = returned(&duplications[0]);
    assert!(duplicate >= 40);
    // fd, exact Linux flock flags, expected incompatibility. This table is
    // independent of descriptor numbers and checks syscall 73 at every call.
    let expected_calls = [
        (a, 5, false),
        (a, 5, false),
        (b, 5, false),
        (c, 6, true),
        (a, 8, false),
        (c, 6, true),
        (b, 8, false),
        (c, 6, false),
        (a, 5, true),
        (b, 6, true),
        (c, 6, false),
        (c, 8, false),
        (a, 6, false),
        (a, 5, false),
        (b, 1, false),
        (b, 8, false),
        (a, 8, false),
        (a, 1, false),
        (a, 2, false),
        (a, 1, false),
        (b, 5, false),
        (c, 6, true),
        (a, 8, false),
        (b, 8, false),
        (c, 8, false),
        (owner, 6, false),
        (competitor, 5, true),
        (duplicate, 8, false),
        (competitor, 6, false),
        (owner, 5, true),
        (competitor, 8, false),
        (owner, 6, false),
        (duplicate, 5, false),
        (competitor, 5, false),
        (competitor, 8, false),
        (duplicate, 6, false),
        (competitor, 5, true),
        (competitor, 6, false),
        (competitor, 8, false),
    ];
    let locks = calls(&events, "flock");
    assert_eq!(
        locks.len(),
        expected_calls.len(),
        "closed owners must not call host: {events}"
    );
    for (call, (fd, flags, blocked)) in locks.iter().zip(expected_calls) {
        assert_eq!(fd_argument(call), fd, "{events}");
        assert_eq!(lock_flags(call), flags, "{events}");
        if blocked {
            assert_eq!(returned(call), -1, "{events}");
            assert!(call.text.contains("EAGAIN"), "{call:?}");
        } else {
            assert_eq!(returned(call), 0, "{events}");
        }
    }
    successful_closes(&events, &[a, b, c, owner, duplicate, competitor]);
    assert_eq!(
        calls(&events, "lseek").len(),
        11,
        "only fixture cursor observations: {events}"
    );
    assert_eq!(
        calls(&events, "fcntl").len(),
        12,
        "only fixture status observations and one duplicate: {events}"
    );
    assert_eq!(
        calls(&events, "fcntl")
            .iter()
            .filter(|call| call.text.contains("F_GETFL"))
            .count(),
        11,
        "{events}"
    );
    assert!(
        calls(&events, "read").is_empty() && calls(&events, "write").is_empty(),
        "locks perform no content I/O: {events}"
    );
    unchanged_and_released(&directory, &expected);
}

#[test]
fn file_lock_and_unlock_faults_are_single_attempts_and_preserve_live_owners() {
    let executable = executable("fault");
    let directory = Directory::new();
    let expected = seed();
    let faults = [
        ("error=EINTR", 4),
        ("error=EAGAIN", 11),
        ("error=EBADF", 9),
        ("error=ENOLCK", 37),
        ("error=EIO", 5),
        ("retval=1", 96),
        ("retval=4294967296", 96),
    ];
    for mode in 0..=1 {
        for fault in std::iter::once(None).chain(faults.iter().map(Some)) {
            fs::write(directory.path().join("input"), &expected).unwrap();
            let injection = fault.map(|(value, _)| format!("flock:{value}:when={}", mode + 1));
            let (output, events) = run(&executable, &directory, Some(mode), injection.as_deref());
            assert_eq!(output.stdout.len(), 4, "{output:?}\n{events}");
            assert_eq!(
                i32::from_le_bytes(output.stdout[..4].try_into().unwrap()),
                fault.map_or(0, |(_, code)| *code),
                "mode={mode} injection={injection:?}\n{events}"
            );
            let opens = calls(&events, "openat");
            assert_eq!(opens.len(), 1, "{events}");
            let fd = returned(&opens[0]);
            assert!(fd >= 0);
            let locks = calls(&events, "flock");
            assert_eq!(
                locks.len(),
                usize::from(mode) + 1,
                "no retry or hidden unlock: {events}"
            );
            for (index, call) in locks.iter().enumerate() {
                assert_eq!(fd_argument(call), fd, "{events}");
                assert_eq!(lock_flags(call), if index == 0 { 6 } else { 8 }, "{events}");
                assert_eq!(
                    call.text.contains("INJECTED"),
                    fault.is_some() && index == usize::from(mode),
                    "{events}"
                );
            }
            if fault.is_some_and(|(value, _)| *value == "retval=4294967296") {
                assert_eq!(
                    returned(&locks[usize::from(mode)]),
                    4_294_967_296,
                    "actual x86_64 injection must retain all 64 bits: {events}"
                );
            }
            successful_closes(&events, &[fd]);
            assert_eq!(
                calls(&events, "lseek").len(),
                2,
                "only explicit fixture positioning: {events}"
            );
            assert_eq!(
                calls(&events, "fcntl").len(),
                2,
                "only explicit before/after status checks: {events}"
            );
            assert!(
                calls(&events, "fcntl")
                    .iter()
                    .all(|call| call.text.contains("F_GETFL")),
                "{events}"
            );
            assert_eq!(calls(&events, "read").len(), 1, "only mode input: {events}");
            assert_eq!(
                calls(&events, "write").len(),
                1,
                "only result report: {events}"
            );
            unchanged_and_released(&directory, &expected);
        }
    }
    eprintln!("native file-lock fault schedules: 16 (14 injected, 2 ordinary controls)");
}
