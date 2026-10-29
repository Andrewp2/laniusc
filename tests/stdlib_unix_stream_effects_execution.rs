//! Unix stream logical admission, real owner lifetimes and selected faults.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeSet,
    fs,
    os::unix::fs::{FileTypeExt, PermissionsExt},
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    time::Duration,
};

struct Directory(common::TempArtifact);
impl Directory {
    fn new() -> Self {
        let path = common::TempArtifact::new("laniusc_unix_effects", "directory", None);
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
        "tests/fixtures/stdlib_foundation/unix_stream_effects/{name}.lani"
    ));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("Unix stream effects", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("Unix stream {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_unix_effects", name, None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn calls<'a>(events: &'a str, name: &str) -> Vec<&'a str> {
    let prefix = format!("{name}(");
    events
        .lines()
        .filter(|line| line.starts_with(&prefix))
        .collect()
}
fn result(line: &str) -> i64 {
    let token = line
        .rsplit_once('=')
        .unwrap_or_else(|| panic!("missing result: {line}"))
        .1
        .trim()
        .split_whitespace()
        .next()
        .unwrap();
    // strace renders F_GETFL flag words in hexadecimal, including injections.
    let parsed = if let Some(hex) = token.strip_prefix("0x") {
        i64::from_str_radix(hex, 16)
    } else {
        token.parse()
    };
    parsed.unwrap_or_else(|error| panic!("invalid result ({error}): {line}"))
}

// Acquired descriptors are real only when a non-injected kernel call returns
// them. Injection skips that call. A skipped close retires the logical wrapper
// but leaves its actual fd for process-exit cleanup; it is not counted as close.
fn owners(events: &str, expected: usize, residual: usize, pure_phase: bool) {
    let mut logical = BTreeSet::<i64>::new();
    let mut actual = BTreeSet::<i64>::new();
    let mut acquired = 0;
    let mut retired = 0;
    let mut closed = 0;
    let mut phases = 0;
    let mut pure = false;
    let mut done = false;
    let mut executions = 0;
    let mut exits = 0;
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert!(pure_phase && result(line) == 1, "{events}");
            if line.contains("\"P\", 1)") {
                assert!(!pure && !done, "{events}");
                pure = true;
            } else if line.contains("\"p\", 1)") {
                assert!(pure && !done, "{events}");
                pure = false;
                phases += 1;
            } else {
                assert!(
                    line.contains("\"D\", 1)")
                        && !pure
                        && !done
                        && logical.is_empty()
                        && actual.is_empty(),
                    "{events}"
                );
                done = true;
            }
            continue;
        }
        assert!(
            !pure,
            "logical rejection or zero-length operation reached host: {line}"
        );
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            exits += 1;
            continue;
        }
        assert!(!done, "only exit follows D: {events}");
        if line.starts_with("execve(") {
            executions += 1;
            assert_eq!(result(line), 0, "{events}");
            continue;
        }
        let permitted = [
            "socket(",
            "socketpair(",
            "accept4(",
            "fcntl(",
            "close(",
            "bind(",
            "connect(",
            "listen(",
            "sendto(",
            "recvfrom(",
            "shutdown(",
            "poll(",
            "read(0,",
            "write(1,",
        ];
        assert!(
            permitted.iter().any(|prefix| line.starts_with(prefix)),
            "unexpected host/heap service: {line}"
        );
        if line.starts_with("socket(") || line.starts_with("socketpair(") {
            assert!(
                line.contains("AF_UNIX")
                    && line.contains("SOCK_STREAM")
                    && line.contains("SOCK_CLOEXEC")
                    && line.contains("SOCK_NONBLOCK"),
                "atomic creation flags: {events}"
            );
        }
        if line.starts_with("sendto(") {
            assert!(line.contains("MSG_NOSIGNAL"), "{events}");
        }
        if line.starts_with("accept4(") {
            assert!(
                line.contains(", NULL, NULL,")
                    && line.contains("SOCK_CLOEXEC")
                    && line.contains("SOCK_NONBLOCK"),
                "null-peer atomic accept flags: {events}"
            );
        }
        if line.starts_with("close(") {
            let fd: i64 = line
                .strip_prefix("close(")
                .unwrap()
                .split_once(')')
                .unwrap()
                .0
                .trim()
                .parse()
                .unwrap();
            assert!(
                logical.remove(&fd),
                "unknown or retried logical retirement: {events}"
            );
            retired += 1;
            if line.contains("INJECTED") {
                assert!(
                    actual.contains(&fd),
                    "skipped close retains actual descriptor: {events}"
                );
            } else {
                assert_eq!(result(line), 0, "{events}");
                assert!(actual.remove(&fd), "unknown/double kernel close: {events}");
                closed += 1;
            }
        } else if !line.contains("INJECTED") {
            let mut new = Vec::new();
            if line.starts_with("socketpair(") && result(line) == 0 {
                let pair = line.rsplit_once('[').unwrap().1.split_once(']').unwrap().0;
                new = pair
                    .split(',')
                    .map(|value| value.trim().parse::<i64>().unwrap())
                    .collect();
                assert_eq!(new.len(), 2, "{events}");
                assert_ne!(new[0], new[1], "{events}");
            } else if (line.starts_with("socket(")
                || line.starts_with("accept4(")
                || (line.starts_with("fcntl(") && line.contains("F_DUPFD_CLOEXEC")))
                && result(line) >= 0
            {
                new.push(result(line));
            }
            for fd in new {
                assert!(
                    fd >= 3 && logical.insert(fd) && actual.insert(fd),
                    "unique real fd acquisition: {events}"
                );
                acquired += 1;
            }
        }
    }
    assert!(!pure && logical.is_empty(), "unretired wrappers: {events}");
    assert_eq!(
        (acquired, retired, closed, actual.len()),
        (expected, expected, expected - residual, residual),
        "actual residual is released by process exit, not the skipped call: {events}"
    );
    assert_eq!((executions, exits), (1, 1), "{events}");
    assert_eq!(phases, usize::from(pure_phase), "{events}");
    assert_eq!(done, pure_phase, "{events}");
}

fn run(
    executable: &common::TempArtifact,
    directory: &Directory,
    mode: Option<u8>,
    injection: Option<&str>,
) -> (Output, String) {
    let trace = common::TempArtifact::new("laniusc_unix_effects", "trace", None);
    let input = common::TempArtifact::new("laniusc_unix_effects", "mode", None);
    input.write_bytes([mode.unwrap_or(0)]);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=all", "-e", "signal=none"]);
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
        "Unix stream effect lifecycle",
        &mut command,
        Duration::from_secs(8),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    assert_eq!(
        events
            .lines()
            .filter(|line| line.contains("INJECTED"))
            .count(),
        usize::from(injection.is_some()),
        "reached exactly once: {injection:?}\n{events}"
    );
    (output, events)
}

#[test]
fn unix_invalid_views_and_mutated_borrowed_names_make_no_host_call() {
    let executable = executable("bounds");
    let directory = Directory::new();
    let (output, events) = run(&executable, &directory, None, None);
    assert!(output.stdout.is_empty());
    assert_eq!(output.stderr, b"PpD");
    owners(&events, 1, 0, true);
    assert_eq!(calls(&events, "socket").len(), 1);
    assert_eq!(calls(&events, "close").len(), 1);
    for name in [
        "bind",
        "connect",
        "listen",
        "sendto",
        "recvfrom",
        "fcntl",
        "poll",
        "clock_gettime",
    ] {
        assert!(calls(&events, name).is_empty(), "{events}");
    }
}

#[test]
fn unix_pair_clone_transfer_adoption_and_last_descriptor_retirement_are_real() {
    let executable = executable("lifecycle");
    let directory = Directory::new();
    let (output, events) = run(&executable, &directory, None, None);
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
    owners(&events, 3, 0, false);
    assert_eq!(calls(&events, "socketpair").len(), 1);
    assert_eq!(
        calls(&events, "fcntl")
            .iter()
            .filter(|line| line.contains("F_DUPFD_CLOEXEC"))
            .count(),
        1
    );
    assert_eq!(calls(&events, "close").len(), 3);
    assert_eq!(calls(&events, "sendto").len(), 1);
    assert_eq!(calls(&events, "recvfrom").len(), 2);
    assert_eq!(calls(&events, "shutdown").len(), 1);
}

#[test]
fn unix_selected_faults_preserve_bytes_full_width_guards_and_single_attempt_ownership() {
    let executable = executable("fault");
    let directory = Directory::new();
    // mode, one reached injection (None is a genuine kernel baseline), code,value.
    let cases = [
        (0, None, 0, 1),
        (0, Some("socket:error=EINTR:when=1"), 3, 0),
        (0, Some("socket:error=EIO:when=1"), 1005, 0),
        (0, Some("socket:error=EMFILE:when=1"), 1024, 0),
        (0, Some("socket:retval=4294967296:when=1"), 2, 0),
        (1, None, 0, 2),
        (1, Some("socketpair:error=EINTR:when=1"), 3, 0),
        (1, Some("socketpair:error=EIO:when=1"), 1005, 0),
        (1, Some("socketpair:error=EMFILE:when=1"), 1024, 0),
        (1, Some("socketpair:retval=1:when=1"), 2, 0),
        (1, Some("socketpair:retval=4294967296:when=1"), 2, 0),
        (1, Some("socketpair:retval=0:when=1"), 2, 0),
        (2, None, 0, 1),
        (2, Some("fcntl:error=EINTR:when=1"), 3, 0),
        (2, Some("fcntl:error=EIO:when=1"), 1005, 0),
        (2, Some("fcntl:error=EMFILE:when=1"), 1024, 0),
        (2, Some("fcntl:retval=4294967296:when=1"), 2, 0),
        (3, None, 1002, 0),
        (3, Some("connect:error=EINTR:when=1"), 3, 0),
        (3, Some("connect:error=EAGAIN:when=1"), 4, 0),
        (3, Some("connect:error=EIO:when=1"), 1005, 0),
        (3, Some("connect:retval=4294967296:when=1"), 2, 0),
        (4, None, 0, 0),
        (4, Some("bind:error=EINTR:when=1"), 3, 0),
        (4, Some("bind:error=EADDRINUSE:when=1"), 1098, 0),
        (4, Some("bind:error=EIO:when=1"), 1005, 0),
        (4, Some("bind:retval=4294967296:when=1"), 2, 0),
        (5, None, 0, 0),
        (5, Some("listen:error=EINTR:when=1"), 3, 0),
        (5, Some("listen:error=EIO:when=1"), 1005, 0),
        (5, Some("listen:retval=4294967296:when=1"), 2, 0),
        (6, None, 4, 0),
        (6, Some("accept4:error=EINTR:when=1"), 3, 0),
        (6, Some("accept4:error=EIO:when=1"), 1005, 0),
        (6, Some("accept4:retval=4294967296:when=1"), 2, 0),
        (7, None, 0, 4),
        (7, Some("sendto:error=EINTR:when=1"), 3, 0),
        (7, Some("sendto:error=EAGAIN:when=1"), 4, 0),
        (7, Some("sendto:error=EPIPE:when=1"), 1032, 0),
        (7, Some("sendto:retval=4294967296:when=1"), 2, 0),
        (7, Some("sendto:retval=5:when=1"), 2, 0),
        (8, None, 0, 4),
        (8, Some("recvfrom:error=EINTR:when=1"), 3, 0),
        (8, Some("recvfrom:error=EAGAIN:when=1"), 4, 0),
        (8, Some("recvfrom:error=EIO:when=1"), 1005, 0),
        (8, Some("recvfrom:retval=4294967296:when=1"), 2, 0),
        (8, Some("recvfrom:retval=5:when=1"), 2, 0),
        (9, None, 0, 0),
        (9, Some("close:error=EINTR:when=1"), 3, 0),
        (9, Some("close:error=EIO:when=1"), 1005, 0),
        (9, Some("close:retval=4294967296:when=1"), 2, 0),
        (10, None, 0, 1),
        (10, Some("fcntl:error=EINTR:when=1"), 3, 0),
        (10, Some("fcntl:error=EIO:when=1"), 1005, 0),
        (10, Some("fcntl:retval=4294967296:when=1"), 2, 0),
        (11, None, 0, 0),
        (11, Some("shutdown:error=EINTR:when=1"), 3, 0),
        (11, Some("shutdown:error=EIO:when=1"), 1005, 0),
        (11, Some("shutdown:retval=4294967296:when=1"), 2, 0),
        (12, None, 0, 1),
        (12, Some("poll:error=EINTR:when=1"), 3, 0),
        (12, Some("poll:error=EIO:when=1"), 1005, 0),
        (12, Some("poll:retval=4294967296:when=1"), 2, 0),
    ];
    assert_eq!(cases.len(), 63);
    for (mode, injection, code, value) in cases {
        let endpoint = directory.path().join("endpoint");
        if endpoint.exists() {
            fs::remove_file(&endpoint).unwrap();
        }
        let (output, events) = run(&executable, &directory, Some(mode), injection);
        let full_width_injection = injection.is_some_and(|value| {
            value
                .split_once(':')
                .is_some_and(|(_, spec)| spec == "retval=4294967296:when=1")
        });
        let compat_warning=b"strace: Injected return value 4294967296 will be clipped to 0 in compat personality\n";
        assert!(
            output.stderr.is_empty()
                || (full_width_injection && output.stderr.as_slice() == compat_warning),
            "unexpected tool stderr: {output:?}\n{events}"
        );
        if full_width_injection {
            let injected = events
                .lines()
                .find(|line| line.contains("INJECTED"))
                .unwrap();
            let syscall = injection.unwrap().split_once(':').unwrap().0;
            assert!(
                injected.starts_with(&format!("{syscall}(")),
                "scheduled injection identity: {events}"
            );
            assert_eq!(
                result(injected),
                4_294_967_296,
                "actual x86_64 result must retain all 64 bits despite the tool's compat warning: {events}"
            );
        }
        assert_eq!(output.stdout.len(), 12, "{output:?}");
        let report: Vec<i32> = output
            .stdout
            .chunks_exact(4)
            .map(|word| i32::from_le_bytes(word.try_into().unwrap()))
            .collect();
        let active = if (mode <= 1 && code != 0) || mode == 9 {
            0
        } else {
            1
        };
        assert_eq!(
            report,
            [code, value, active],
            "mode={mode} injection={injection:?}\n{events}"
        );
        if full_width_injection {
            assert_eq!(
                report[0], 2,
                "full-width return must be InvalidCount: {events}"
            );
        }
        let acquired = match mode {
            0 => usize::from(code == 0),
            1 => 2 * usize::from(code == 0),
            2 => {
                if code == 0 {
                    3
                } else {
                    2
                }
            }
            7 | 8 | 11 | 12 => 2,
            _ => 1,
        };
        let residual = usize::from(mode == 9 && injection.is_some());
        owners(&events, acquired, residual, false);
        for name in [
            "socket",
            "socketpair",
            "fcntl",
            "connect",
            "bind",
            "listen",
            "accept4",
            "sendto",
            "recvfrom",
            "shutdown",
            "poll",
        ] {
            let expected = match name {
                "socket" => usize::from(matches!(mode, 0 | 3 | 4 | 5 | 6 | 9 | 10)),
                "socketpair" => usize::from(matches!(mode, 1 | 2 | 7 | 8 | 11 | 12)),
                "fcntl" => usize::from(matches!(mode, 2 | 10)),
                "connect" => usize::from(mode == 3),
                "bind" => usize::from(matches!(mode, 4 | 5 | 6)),
                "listen" => usize::from(matches!(mode, 5 | 6)),
                "accept4" => usize::from(mode == 6),
                "sendto" => usize::from(matches!(mode, 7 | 8)),
                "recvfrom" => {
                    if mode == 8 && code != 0 {
                        2
                    } else {
                        usize::from(matches!(mode, 7 | 8 | 11))
                    }
                }
                "shutdown" => usize::from(mode == 11),
                "poll" => usize::from(mode == 12),
                _ => unreachable!(),
            };
            assert_eq!(
                calls(&events, name).len(),
                expected,
                "one attempt, explicit recovery kept distinct: mode={mode} {injection:?}\n{events}"
            );
        }
        let named = mode == 5 || mode == 6 || (mode == 4 && injection.is_none());
        assert_eq!(
            endpoint.exists(),
            named,
            "only genuine bind creates a persistent pathname: {events}"
        );
        if named {
            assert!(fs::metadata(&endpoint).unwrap().file_type().is_socket());
        }
    }
    eprintln!(
        "unix-effects finite_schedules=63 genuine_baselines=13 reached_injections=50 skipped_close_residuals=3"
    );
}
