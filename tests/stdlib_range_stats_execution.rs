//! Admitted x86_64 Linux range_stats application: one compile, 41 native cases.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output, Stdio},
};

fn range_stats_executable() -> common::TempArtifact {
    let repository = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = repository.join("sample_programs/library/range_stats.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(repository.join("stdlib")),
        user_roots: Vec::new(),
    };
    let bytes = common::run_gpu_codegen_with_timeout("range_stats application", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("range_stats: {error}"));
    let executable = common::TempArtifact::new("laniusc_range_stats", "executable", None);
    executable.write_bytes(bytes); // Existing strict shared ELF/jump checker.
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

#[derive(Debug)]
struct RangeStatsTrace {
    text: String,
    attempt_lengths: Vec<usize>,
    successful_lengths: Vec<usize>,
    // (one-based mmap attempt ordinal, requested length)
    failures: Vec<(usize, usize)>,
    // Zero-based successful-allocation identities, not just sizes. Addresses
    // may be reused only after their prior owner was released.
    release_ids: Vec<usize>,
}

fn range_stats_syscall_result<'a>(
    arguments: &'a str,
    line: &str,
    events: &str,
) -> (&'a str, &'a str) {
    // strace aligns the result column, especially for short munmap calls.
    // Parse the closing argument delimiter and '=' independently of spacing.
    let (arguments, tail) = arguments.split_once(')').unwrap_or_else(|| {
        panic!("missing syscall argument terminator: {line}\nfull memory trace:\n{events}")
    });
    let result = tail.trim_start().strip_prefix('=').unwrap_or_else(|| {
        panic!("missing syscall result separator: {line}\nfull memory trace:\n{events}")
    });
    (arguments, result.trim())
}

fn range_stats_memory_trace(text: String) -> RangeStatsTrace {
    let mut live = BTreeMap::<String, (usize, usize)>::new();
    let mut trace = RangeStatsTrace {
        text,
        attempt_lengths: Vec::new(),
        successful_lengths: Vec::new(),
        failures: Vec::new(),
        release_ids: Vec::new(),
    };
    for line in trace.text.lines() {
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let (arguments, result) = range_stats_syscall_result(arguments, line, &trace.text);
            let mut arguments = arguments.split(',');
            assert_eq!(arguments.next().unwrap().trim(), "NULL", "{}", trace.text);
            let length: usize = arguments.next().unwrap().trim().parse().unwrap();
            assert!(length > 0, "{}", trace.text);
            trace.attempt_lengths.push(length);
            let address = result.split_whitespace().next().unwrap();
            if address.starts_with("0x") {
                assert!(!result.contains("INJECTED"), "{}", trace.text);
                let id = trace.successful_lengths.len();
                assert!(
                    live.insert(address.to_owned(), (id, length)).is_none(),
                    "{}",
                    trace.text
                );
                trace.successful_lengths.push(length);
            } else {
                assert_eq!(address, "-1", "{}", trace.text);
                assert!(
                    result.contains("ENOMEM") && result.contains("INJECTED"),
                    "{}",
                    trace.text
                );
                trace.failures.push((trace.attempt_lengths.len(), length));
            }
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = range_stats_syscall_result(arguments, line, &trace.text);
            assert_eq!(result.trim(), "0", "{}", trace.text);
            let (address, length) = arguments.split_once(',').unwrap();
            let length: usize = length.trim().parse().unwrap();
            let (id, owned_length) = live.remove(address.trim()).unwrap_or_else(|| {
                panic!("release of unknown/already released owner: {}", trace.text)
            });
            assert_eq!(length, owned_length, "{}", trace.text);
            trace.release_ids.push(id);
        } else {
            // Includes mremap: this application makes only the fixed snapshot
            // allocations; iteration and output staging never grow storage.
            panic!("unexpected memory event: {}", trace.text);
        }
    }
    assert!(live.is_empty(), "unreleased owners: {}", trace.text);
    trace
}

fn range_stats_exact_profile(
    trace: &RangeStatsTrace,
    attempts: &[usize],
    successful: &[usize],
    releases: &[usize],
    failures: &[(usize, usize)],
) {
    assert_eq!(trace.attempt_lengths.as_slice(), attempts, "{}", trace.text);
    assert_eq!(
        trace.successful_lengths.as_slice(),
        successful,
        "{}",
        trace.text
    );
    assert_eq!(trace.release_ids.as_slice(), releases, "{}", trace.text);
    assert_eq!(trace.failures.as_slice(), failures, "{}", trace.text);
}

fn range_stats_run(
    executable: &common::TempArtifact,
    arguments: &[&str],
    injections: &[&str],
    closed_stdout: bool,
) -> (Output, String, RangeStatsTrace) {
    let trace = common::TempArtifact::new("laniusc_range_stats", "trace", None);
    let mut command = Command::new("timeout");
    command
        .args(["--kill-after=1s", "8s", "strace", "-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=rt_sigaction,read,write,mmap,mremap,munmap",
            "-e",
            "signal=none",
        ]);
    for injection in injections {
        command.arg("-e").arg(injection);
    }
    command
        .arg(executable.path())
        .args(arguments)
        .stdin(Stdio::null());
    if closed_stdout {
        let (reader, writer) = std::io::pipe().unwrap();
        drop(reader);
        command.stdout(writer);
    }
    // Existing bounded real-closed-pipe pattern: standard output() preserves
    // explicit redirection, whereas the common capturing helper replaces it.
    let output = command.output().expect("bounded range_stats native case");
    let events = fs::read_to_string(trace.path()).unwrap();
    let memory = events
        .lines()
        .filter(|line| {
            line.starts_with("mmap(") || line.starts_with("munmap(") || line.starts_with("mremap(")
        })
        .collect::<Vec<_>>()
        .join("\n");
    (output, events, range_stats_memory_trace(memory))
}

fn range_stats_policy(events: &str, success: bool) {
    let lines = events.lines().collect::<Vec<_>>();
    let actions = lines
        .iter()
        .enumerate()
        .filter(|(_, line)| line.starts_with("rt_sigaction("))
        .collect::<Vec<_>>();
    assert_eq!(actions.len(), 1, "{events}");
    let (position, action) = actions[0];
    assert!(
        action.contains("SIGPIPE") && action.contains("SIG_IGN"),
        "{events}"
    );
    if success {
        assert_eq!(action.rsplit_once('=').unwrap().1.trim(), "0", "{events}");
    } else {
        assert!(
            action.contains("EINTR") && action.contains("INJECTED"),
            "{events}"
        );
    }
    if let Some(next) = lines
        .iter()
        .position(|line| line.starts_with("mmap(") || line.starts_with("write("))
    {
        assert!(
            position < next,
            "signal policy must precede allocation/output: {events}"
        );
    }
    assert!(
        !lines.iter().any(|line| line.starts_with("read(")),
        "no stdin input is used: {events}"
    );
}

// Arguments has one Vec<View<u8>> allocation followed by its packed bytes.
// A View<u8> is five native words: slice(3), start(1), length(1), hence40bytes
// under this x86 profile. The snapshot preflights count and total-byte limits.
fn range_stats_argument_sizes(arguments: &[&str]) -> Vec<usize> {
    let total: usize = arguments.iter().map(|item| item.len()).sum();
    if arguments.len() > 3 || total > 96 {
        return Vec::new();
    }
    let mut sizes = Vec::new();
    if !arguments.is_empty() {
        sizes.push(arguments.len() * 40);
    }
    if total != 0 {
        sizes.push(total);
    }
    sizes
}

fn range_stats_argument_profile(
    trace: &RangeStatsTrace,
    arguments: &[&str],
    failed: Option<usize>,
) {
    let sizes = range_stats_argument_sizes(arguments);
    if let Some(ordinal) = failed {
        let releases = (0..ordinal - 1).collect::<Vec<_>>();
        range_stats_exact_profile(
            trace,
            &sizes[..ordinal],
            &sizes[..ordinal - 1],
            &releases,
            &[(ordinal, sizes[ordinal - 1])],
        );
    } else {
        // Arguments.destroy releases entries first and packed bytes second.
        let releases = (0..sizes.len()).collect::<Vec<_>>();
        range_stats_exact_profile(trace, &sizes, &sizes, &releases, &[]);
    }
}

// Closed-form independent oracle; production actually walks RangeI32 + Take.
fn range_stats_expected(start: i32, end: i32, limit: u64) -> Vec<u8> {
    let available = if start > end {
        0
    } else {
        (i64::from(end) - i64::from(start) + 1) as u64
    };
    let count = available.min(limit);
    let n = i128::from(count);
    let sum = n * (2 * i128::from(start) + n - 1) / 2;
    format!("count,sum\n{count},{sum}\n").into_bytes()
}

fn range_stats_assert_no_write(events: &str) {
    assert!(
        !events.lines().any(|line| line.starts_with("write(")),
        "{events}"
    );
}

#[test]
fn range_stats_csv_arguments_and_exact_failure_cleanup() {
    // One compile/strict ELF check shared by every normal and fault case.
    let executable = range_stats_executable();
    let cases: &[(i32, i32, u64)] = &[
        (1, 5, 10),
        (-5, 5, 4),
        (i32::MIN, i32::MAX, 7),
        (i32::MAX, i32::MAX, 1),
        (i32::MIN, i32::MIN, 1),
        (i32::MAX - 2, i32::MAX, 10),
        (i32::MIN, i32::MIN + 2, 10),
        (9, 3, 10),
        (i32::MIN, i32::MAX, 0),
        (-3, -1, 2),
        (i32::MIN, i32::MAX, 1_000_000),
        (i32::MAX - 999_999, i32::MAX, 1_000_000),
    ];
    for &(start, end, limit) in cases {
        let owned = [start.to_string(), end.to_string(), limit.to_string()];
        let arguments = owned.iter().map(String::as_str).collect::<Vec<_>>();
        let (output, events, trace) = range_stats_run(&executable, &arguments, &[], false);
        assert_eq!(
            output.status.code(),
            Some(0),
            "{arguments:?}: {output:?}\n{events}"
        );
        assert_eq!(
            output.stdout,
            range_stats_expected(start, end, limit),
            "{events}"
        );
        assert!(output.stderr.is_empty(), "{output:?}");
        range_stats_policy(&events, true);
        range_stats_argument_profile(&trace, &arguments, None);
    }
    // Existing strict decimal grammar permits leading signs for i32 and
    // leading zeroes, while still requiring the complete ASCII input.
    let arguments = ["-0002", "+0002", "0005"];
    let (output, events, trace) = range_stats_run(&executable, &arguments, &[], false);
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    assert_eq!(output.stdout, range_stats_expected(-2, 2, 5));
    assert!(output.stderr.is_empty());
    range_stats_policy(&events, true);
    range_stats_argument_profile(&trace, &arguments, None);

    let malformed: &[&[&str]] = &[
        &[],
        &["1"],
        &["1", "2"],
        &["1", "2", "3", "4"],
        &["", "", ""],
        &["", "2", "3"],
        &["-", "2", "3"],
        &["+", "2", "3"],
        &[" 1", "2", "3"],
        &["1 ", "2", "3"],
        &["1x", "2", "3"],
        &["1.0", "2", "3"],
        &["2147483648", "2", "3"],
        &["-2147483649", "2", "3"],
        &["1", "2147483648", "3"],
        &["1", "2", "-1"],
        &["1", "2", "+1"],
        &["1", "2", "1000001"],
        &["1", "2", "18446744073709551615"],
        &["1", "2", "18446744073709551616"],
        &["1", "2", "1\n"],
        &["١", "2", "3"],
    ];
    for &arguments in malformed {
        let (output, events, trace) = range_stats_run(&executable, arguments, &[], false);
        assert_eq!(
            output.status.code(),
            Some(2),
            "{arguments:?}: {output:?}\n{events}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        range_stats_policy(&events, true);
        range_stats_assert_no_write(&events);
        range_stats_argument_profile(&trace, arguments, None);
    }
    let too_long = "9".repeat(97);
    let arguments = [too_long.as_str(), "2", "3"];
    let (output, events, trace) = range_stats_run(&executable, &arguments, &[], false);
    assert_eq!(output.status.code(), Some(2), "{output:?}\n{events}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
    range_stats_policy(&events, true);
    range_stats_assert_no_write(&events);
    range_stats_argument_profile(&trace, &arguments, None);

    let arguments = ["-2", "2", "5"]; // Exactly120 entry bytes +4 argument bytes.
    for ordinal in 1..=2 {
        let injection = format!("inject=mmap:error=ENOMEM:when={ordinal}");
        let (output, events, trace) =
            range_stats_run(&executable, &arguments, &[&injection], false);
        assert_eq!(output.status.code(), Some(4), "{output:?}\n{events}");
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
        range_stats_policy(&events, true);
        range_stats_assert_no_write(&events);
        range_stats_argument_profile(&trace, &arguments, Some(ordinal));
    }
    let (output, events, trace) = range_stats_run(
        &executable,
        &arguments,
        &["inject=write:error=EIO:when=1"],
        false,
    );
    assert_eq!(output.status.code(), Some(3), "{output:?}\n{events}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
    range_stats_policy(&events, true);
    range_stats_argument_profile(&trace, &arguments, None);
    let writes = events
        .lines()
        .filter(|line| line.starts_with("write("))
        .collect::<Vec<_>>();
    assert_eq!(writes.len(), 1, "{events}");
    assert!(
        writes[0].starts_with("write(1,")
            && writes[0].contains("EIO")
            && writes[0].contains("INJECTED"),
        "{events}"
    );

    let (output, events, trace) = range_stats_run(&executable, &arguments, &[], true);
    assert_eq!(output.status.code(), Some(3), "{output:?}\n{events}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
    range_stats_policy(&events, true);
    range_stats_argument_profile(&trace, &arguments, None);
    assert!(
        events
            .lines()
            .any(|line| line.starts_with("write(1,") && line.contains("EPIPE")),
        "{events}"
    );

    let (output, events, trace) = range_stats_run(
        &executable,
        &arguments,
        &["inject=rt_sigaction:error=EINTR:when=1"],
        false,
    );
    assert_eq!(output.status.code(), Some(3), "{output:?}\n{events}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
    range_stats_policy(&events, false);
    range_stats_assert_no_write(&events);
    range_stats_exact_profile(&trace, &[], &[], &[], &[]);
}
