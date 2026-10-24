//! Real bounded file-copy application, with one compile shared by all cases.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::{BTreeMap, BTreeSet},
    ffi::{OsStr, OsString},
    fs,
    os::unix::{
        ffi::{OsStrExt, OsStringExt},
        fs::{FileTypeExt, PermissionsExt, symlink},
    },
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    time::Duration,
};

struct Directory(common::TempArtifact);
impl Directory {
    fn new() -> Self {
        let path = common::TempArtifact::new("laniusc_copy_file", "directory", None);
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

fn executable() -> common::TempArtifact {
    let repository = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = repository.join("sample_programs/library/copy_file.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(repository.join("stdlib")),
        user_roots: Vec::new(),
    };
    let bytes = common::run_gpu_codegen_with_timeout("copy_file application", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("copy_file: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_copy_file", "executable", None);
    // The shared writer applies the unchanged strict ELF/jump checker.
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn arguments(
    source: impl AsRef<OsStr>,
    destination: impl AsRef<OsStr>,
    limit: impl AsRef<OsStr>,
) -> Vec<OsString> {
    vec![
        source.as_ref().to_owned(),
        destination.as_ref().to_owned(),
        limit.as_ref().to_owned(),
    ]
}

fn calls<'a>(events: &'a str, name: &str) -> Vec<&'a str> {
    let prefix = format!("{name}(");
    events
        .lines()
        .filter(|line| line.starts_with(&prefix))
        .collect()
}

fn syscall_result<'a>(line: &'a str, name: &str) -> (&'a str, &'a str) {
    let arguments = line.strip_prefix(name).unwrap().strip_prefix('(').unwrap();
    // Result columns have variable alignment. Split at the final '=' and
    // trim the argument terminator separately. Error text and (INJECTED)
    // may also contain ')', so the last ')' is not the argument terminator.
    let (arguments, result) = arguments
        .rsplit_once('=')
        .unwrap_or_else(|| panic!("missing syscall result separator: {line}"));
    let arguments = arguments
        .trim_end()
        .strip_suffix(')')
        .unwrap_or_else(|| panic!("missing syscall argument terminator: {line}"));
    (arguments, result.trim())
}

#[derive(Debug)]
struct MemoryTrace {
    attempts: usize,
    successful: usize,
    releases: usize,
    failed_ordinals: Vec<usize>,
}

fn memory_trace(events: &str) -> MemoryTrace {
    let mut live = BTreeMap::<u64, usize>::new();
    let mut trace = MemoryTrace {
        attempts: 0,
        successful: 0,
        releases: 0,
        failed_ordinals: Vec::new(),
    };
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let (arguments, result) = syscall_result(line, "mmap");
            let mut fields = arguments.split(',').map(str::trim);
            assert_eq!(fields.next(), Some("NULL"), "{events}");
            let length: usize = fields.next().unwrap().parse().unwrap();
            assert!(length > 0, "{events}");
            trace.attempts += 1;
            let address = result.split_whitespace().next().unwrap();
            if let Some(address) = address.strip_prefix("0x") {
                assert!(!result.contains("INJECTED"), "{events}");
                let address = u64::from_str_radix(address, 16).unwrap();
                assert!(live.insert(address, length).is_none(), "{events}");
                trace.successful += 1;
            } else {
                assert_eq!(address, "-1", "{events}");
                assert!(
                    result.contains("ENOMEM") && result.contains("INJECTED"),
                    "{events}"
                );
                trace.failed_ordinals.push(trace.attempts);
            }
        } else if line.starts_with("munmap(") {
            let (arguments, result) = syscall_result(line, "munmap");
            assert_eq!(result, "0", "{events}");
            let (address, length) = arguments.split_once(',').unwrap();
            let address =
                u64::from_str_radix(address.trim().strip_prefix("0x").unwrap(), 16).unwrap();
            let length: usize = length.trim().parse().unwrap();
            let owned_length = live.remove(&address).unwrap_or_else(|| {
                panic!("release of unknown/already released allocation: {events}")
            });
            assert_eq!(length, owned_length, "{events}");
            trace.releases += 1;
        } else if line.starts_with("mremap(") {
            panic!("fixed argument snapshot must not grow storage: {events}");
        }
        // The trace also contains file syscalls. They do not enter the live
        // allocation oracle; they are checked by separate ownership assertions.
    }
    assert!(
        live.is_empty(),
        "unreleased allocation owners {live:?}: {events}"
    );
    assert_eq!(trace.releases, trace.successful, "{events}");
    trace
}

fn snapshot_profile(
    trace: &MemoryTrace,
    arguments: &[OsString],
    failed: Option<usize>,
    events: &str,
) {
    let total: usize = arguments
        .iter()
        .map(|argument| argument.as_bytes().len())
        .sum();
    let normal_attempts = if arguments.len() > 3 || total > 8210 {
        0
    } else {
        usize::from(!arguments.is_empty()) + usize::from(total != 0)
    };
    if let Some(ordinal) = failed {
        assert!((1..=normal_attempts).contains(&ordinal), "{arguments:?}");
        assert_eq!(trace.attempts, ordinal, "{events}");
        assert_eq!(trace.successful, ordinal - 1, "{events}");
        assert_eq!(trace.failed_ordinals, [ordinal], "{events}");
    } else {
        assert_eq!(trace.attempts, normal_attempts, "{events}");
        assert_eq!(trace.successful, normal_attempts, "{events}");
        assert!(trace.failed_ordinals.is_empty(), "{events}");
    }
    // The entry allocation's physical View width is deliberately unspecified.
    // Every successful requested length was instead matched to its release.
}

fn descriptor_owners(events: &str) {
    let mut live = BTreeSet::<i32>::new();
    let mut open_ordinal = 0;
    for line in events.lines() {
        if line.starts_with("openat(") {
            open_ordinal += 1;
            assert!(open_ordinal <= 2, "unexpected open/retry: {events}");
            for flag in ["O_NONBLOCK", "O_NOFOLLOW", "O_CLOEXEC"] {
                assert!(line.contains(flag), "missing {flag}: {events}");
            }
            assert!(
                !line.contains("O_TRUNC") && !line.contains("O_APPEND"),
                "{events}"
            );
            if open_ordinal == 1 {
                assert!(
                    line.contains("O_RDONLY") && !line.contains("O_CREAT"),
                    "{events}"
                );
            } else {
                assert!(
                    line.contains("O_WRONLY") && line.contains("O_CREAT"),
                    "{events}"
                );
                assert!(
                    syscall_result(line, "openat").0.ends_with("0666"),
                    "{events}"
                );
            }
            let (_, result) = syscall_result(line, "openat");
            let descriptor: i32 = result.split_whitespace().next().unwrap().parse().unwrap();
            if descriptor >= 0 {
                assert!(live.insert(descriptor), "duplicate active owner: {events}");
            }
        } else if line.starts_with("close(") {
            let (descriptor, _) = syscall_result(line, "close");
            let descriptor: i32 = descriptor.trim().parse().unwrap();
            // A close error still retires the logical File owner. Injected
            // close errors skip the real syscall, so this is an attempt and
            // ownership-retirement oracle, not evidence of kernel release.
            assert!(
                live.remove(&descriptor),
                "unknown/repeated close attempt: {events}"
            );
        }
    }
    assert!(
        live.is_empty(),
        "owned descriptors lack a close attempt: {live:?}\n{events}"
    );
    assert!(calls(events, "rt_sigaction").is_empty(), "{events}");
}

struct NativeRun {
    output: Output,
    events: String,
    memory: MemoryTrace,
}

fn run(
    executable: &common::TempArtifact,
    directory: &Directory,
    arguments: &[OsString],
    injection: Option<&str>,
) -> NativeRun {
    let trace = common::TempArtifact::new("laniusc_copy_file", "trace", None);
    let mut command = Command::new("strace");
    command.args(["-qq", "-o"]).arg(trace.path()).args([
        "-e",
        "trace=openat,fcntl,statx,lseek,ftruncate,read,write,close,mmap,mremap,munmap,rt_sigaction",
        "-e",
        "signal=none",
    ]);
    if let Some(injection) = injection {
        command.arg("-e").arg(format!("inject={injection}"));
    }
    command
        .arg(executable.path())
        .args(arguments)
        .current_dir(directory.path())
        .stdin(Stdio::null());
    let output = common::process_output_with_timeout(
        "copy_file native case",
        &mut command,
        Duration::from_secs(5),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    if let Some(injection) = injection {
        let (syscall, _) = injection.split_once(':').unwrap();
        let reached = calls(&events, syscall)
            .into_iter()
            .filter(|line| line.contains("INJECTED"))
            .collect::<Vec<_>>();
        assert_eq!(reached.len(), 1, "unreached/repeated {injection}: {events}");
        let errno = injection
            .split("error=")
            .nth(1)
            .unwrap()
            .split(':')
            .next()
            .unwrap();
        assert!(reached[0].contains(errno), "{injection}: {events}");
    } else {
        assert!(!events.contains("INJECTED"), "{events}");
    }
    let memory = memory_trace(&events);
    descriptor_owners(&events);
    NativeRun {
        output,
        events,
        memory,
    }
}

fn checked(run: &NativeRun, status: i32) {
    assert_eq!(
        run.output.status.code(),
        Some(status),
        "{:?}\n{}",
        run.output,
        run.events
    );
    assert!(
        run.output.stdout.is_empty() && run.output.stderr.is_empty(),
        "{:?}\n{}",
        run.output,
        run.events
    );
}

fn normal_case(
    executable: &common::TempArtifact,
    directory: &Directory,
    arguments: &[OsString],
    status: i32,
) -> NativeRun {
    let result = run(executable, directory, arguments, None);
    checked(&result, status);
    snapshot_profile(&result.memory, arguments, None, &result.events);
    result
}

fn call_count(run: &NativeRun, syscall: &str, expected: usize) {
    assert_eq!(
        calls(&run.events, syscall).len(),
        expected,
        "{}",
        run.events
    );
}

fn bytes(directory: &Directory, name: impl AsRef<Path>, expected: &[u8]) {
    assert_eq!(fs::read(directory.path().join(name)).unwrap(), expected);
}

fn binary(length: usize) -> Vec<u8> {
    (0..length)
        .map(|index| (index.wrapping_mul(37).wrapping_add(11)) as u8)
        .collect()
}

#[test]
fn copy_file_bytes_arguments_policies_and_exact_failure_cleanup() {
    // One production-root compile and strict native checker for all cases.
    let executable = executable();
    let directory = Directory::new();
    let source = directory.path().join("source");
    let destination = directory.path().join("destination");
    let sentinel = b"existing destination tail that must disappear only after validation";

    for length in [0, 1, 1023, 1024, 1025, 4097] {
        let data = binary(length);
        fs::write(&source, &data).unwrap();
        for existing in [false, true] {
            let _ = fs::remove_file(&destination);
            if existing {
                let mut old = binary(length + 29);
                old.extend_from_slice(sentinel);
                fs::write(&destination, old).unwrap();
            }
            let args = arguments("source", "destination", (length + 17).to_string());
            let result = normal_case(&executable, &directory, &args, 0);
            bytes(&directory, "source", &data);
            bytes(&directory, "destination", &data);
            call_count(&result, "openat", 2);
            call_count(&result, "ftruncate", 1);
            call_count(&result, "close", 2);
        }
    }

    for (length, limit, status) in [(0, 0, 0), (1, 0, 5), (1025, 1025, 0), (1025, 1024, 5)] {
        let data = binary(length);
        fs::write(&source, &data).unwrap();
        fs::write(&destination, sentinel).unwrap();
        let args = arguments("source", "destination", limit.to_string());
        let result = normal_case(&executable, &directory, &args, status);
        bytes(&directory, "source", &data);
        bytes(&directory, "destination", &data[..length.min(limit)]);
        call_count(&result, "close", 2);
        let reads = calls(&result.events, "read");
        let (probe_arguments, probe_result) = syscall_result(reads.last().unwrap(), "read");
        assert_eq!(
            probe_arguments.rsplit_once(',').unwrap().1.trim(),
            "1",
            "{}",
            result.events
        );
        assert_eq!(
            probe_result,
            if status == 5 { "1" } else { "0" },
            "{}",
            result.events
        );
    }

    let raw_source = OsString::from_vec(vec![b's', 255, b'\n']);
    let raw_destination = OsString::from_vec(vec![b'd', 128, b'\n']);
    let data = binary(1025);
    fs::write(directory.path().join(&raw_source), &data).unwrap();
    fs::write(directory.path().join(&raw_destination), sentinel).unwrap();
    // A long leading-zero spelling is legal within the total snapshot budget.
    let args = arguments(
        &raw_source,
        &raw_destination,
        format!("{}1025", "0".repeat(24)),
    );
    normal_case(&executable, &directory, &args, 0);
    bytes(&directory, &raw_source, &data);
    bytes(&directory, &raw_destination, &data);
    fs::write(&source, b"small").unwrap();
    let args = arguments("source", "destination", i64::MAX.to_string());
    normal_case(&executable, &directory, &args, 0);
    bytes(&directory, "source", b"small");
    bytes(&directory, "destination", b"small");

    let mut malformed = vec![
        Vec::new(),
        vec!["source".into()],
        vec!["source".into(), "destination".into()],
        vec![
            "source".into(),
            "destination".into(),
            "5".into(),
            "extra".into(),
        ],
        arguments("", "destination", "5"),
        arguments("source", "", "5"),
    ];
    for limit in [
        "",
        "+1",
        "-1",
        " 1",
        "1 ",
        "1\n",
        "1x",
        "1.0",
        "١",
        "9223372036854775808",
        "18446744073709551615",
        "18446744073709551616",
    ] {
        malformed.push(arguments("source", "destination", limit));
    }
    malformed.push(arguments(
        OsString::from_vec(vec![255]),
        "destination",
        "+1",
    ));
    malformed.push(arguments("x".repeat(4096), "destination", "5"));
    malformed.push(arguments("source", "x".repeat(4096), "5"));
    malformed.push(arguments("source", "destination", "0".repeat(8211)));
    for args in malformed {
        fs::write(&source, &data).unwrap();
        fs::write(&destination, sentinel).unwrap();
        let result = normal_case(&executable, &directory, &args, 2);
        for syscall in ["openat", "ftruncate", "read", "write", "close"] {
            call_count(&result, syscall, 0);
        }
        bytes(&directory, "source", &data);
        bytes(&directory, "destination", sentinel);
    }

    fs::write(&source, &data).unwrap();
    fs::hard_link(&source, directory.path().join("hardlink")).unwrap();
    for alias in ["source", "hardlink"] {
        let args = arguments("source", alias, "2048");
        let result = normal_case(&executable, &directory, &args, 3);
        call_count(&result, "ftruncate", 0);
        call_count(&result, "read", 0);
        call_count(&result, "close", 2);
        bytes(&directory, "source", &data);
        bytes(&directory, "hardlink", &data);
    }

    symlink("source", directory.path().join("source-link")).unwrap();
    symlink("destination", directory.path().join("destination-link")).unwrap();
    for (from, to, expected_opens, expected_closes) in [
        ("source-link", "destination", 1, 0),
        ("source", "destination-link", 2, 1),
    ] {
        fs::write(&destination, sentinel).unwrap();
        let args = arguments(from, to, "2048");
        let result = normal_case(&executable, &directory, &args, 3);
        call_count(&result, "openat", expected_opens);
        call_count(&result, "close", expected_closes);
        call_count(&result, "ftruncate", 0);
        assert!(result.events.contains("ELOOP"), "{}", result.events);
        bytes(&directory, "source", &data);
        bytes(&directory, "destination", sentinel);
    }
    fs::create_dir(directory.path().join("real-directory")).unwrap();
    symlink("real-directory", directory.path().join("directory-link")).unwrap();
    fs::write(directory.path().join("real-directory/input"), &data).unwrap();
    let args = arguments("directory-link/input", "directory-link/output", "2048");
    normal_case(&executable, &directory, &args, 0);
    bytes(&directory, "real-directory/input", &data);
    bytes(&directory, "real-directory/output", &data);

    let fifo = directory.path().join("fifo");
    let setup = common::process_output_with_timeout(
        "copy_file FIFO setup",
        Command::new("mkfifo").arg(&fifo),
        Duration::from_secs(5),
    );
    common::assert_command_success("mkfifo", &setup);
    for (from, to, expected_closes) in [("fifo", "destination", 2), ("source", "fifo", 1)] {
        fs::write(&destination, sentinel).unwrap();
        let args = arguments(from, to, "2048");
        let result = normal_case(&executable, &directory, &args, 3);
        call_count(&result, "openat", 2);
        call_count(&result, "close", expected_closes);
        call_count(&result, "ftruncate", 0);
        call_count(&result, "read", 0);
        bytes(&directory, "source", &data);
        bytes(&directory, "destination", sentinel);
        assert!(fs::symlink_metadata(&fifo).unwrap().file_type().is_fifo());
    }

    // First and second open faults leave the existing destination unchanged.
    // Later transfer faults preserve the acknowledged prefix after truncation.
    // A skipped injected close checks attempts/logical retirement, not actual
    // Linux descriptor release; the process releases skipped descriptors at exit.
    let data = binary(4097);
    let args = arguments("source", "destination", "8192");
    for (injection, prefix, open_count, close_count, truncates, reads, writes) in [
        ("openat:error=EACCES:when=1", None, 1, 0, 0, 0, 0),
        ("openat:error=EACCES:when=2", None, 2, 1, 0, 0, 0),
        ("ftruncate:error=EIO:when=1", None, 2, 2, 1, 0, 0),
        ("read:error=EIO:when=2", Some(1024), 2, 2, 1, 2, 1),
        ("read:error=EINTR:when=2", Some(1024), 2, 2, 1, 2, 1),
        ("write:error=EIO:when=2", Some(1024), 2, 2, 1, 2, 2),
        ("write:error=EINTR:when=2", Some(1024), 2, 2, 1, 2, 2),
        ("close:error=EIO:when=1", Some(data.len()), 2, 2, 1, 6, 5),
        ("close:error=EINTR:when=2", Some(data.len()), 2, 2, 1, 6, 5),
    ] {
        fs::write(&source, &data).unwrap();
        fs::write(&destination, sentinel).unwrap();
        let result = run(&executable, &directory, &args, Some(injection));
        checked(&result, 3);
        snapshot_profile(&result.memory, &args, None, &result.events);
        for (syscall, expected) in [
            ("openat", open_count),
            ("close", close_count),
            ("ftruncate", truncates),
            ("read", reads),
            ("write", writes),
        ] {
            call_count(&result, syscall, expected);
        }
        bytes(&directory, "source", &data);
        bytes(
            &directory,
            "destination",
            prefix.map_or(sentinel.as_slice(), |length| &data[..length]),
        );
    }

    // Close failure takes precedence over an already detected quota failure.
    fs::write(&source, &data).unwrap();
    fs::write(&destination, sentinel).unwrap();
    let quota_args = arguments("source", "destination", "1024");
    let result = run(
        &executable,
        &directory,
        &quota_args,
        Some("close:error=EIO:when=1"),
    );
    checked(&result, 3);
    snapshot_profile(&result.memory, &quota_args, None, &result.events);
    call_count(&result, "close", 2);
    bytes(&directory, "source", &data);
    bytes(&directory, "destination", &data[..1024]);

    for ordinal in 1..=2 {
        fs::write(&source, &data).unwrap();
        fs::write(&destination, sentinel).unwrap();
        let injection = format!("mmap:error=ENOMEM:when={ordinal}");
        let result = run(&executable, &directory, &args, Some(&injection));
        checked(&result, 4);
        snapshot_profile(&result.memory, &args, Some(ordinal), &result.events);
        for syscall in ["openat", "ftruncate", "read", "write", "close"] {
            call_count(&result, syscall, 0);
        }
        bytes(&directory, "source", &data);
        bytes(&directory, "destination", sentinel);
    }
}
