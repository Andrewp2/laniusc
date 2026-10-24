//! Borrowed iterator composition in the real checked range-dot application.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    ffi::OsString,
    fs,
    os::unix::{
        ffi::{OsStrExt, OsStringExt},
        fs::PermissionsExt,
    },
    path::PathBuf,
    process::{Command, Output, Stdio},
};

fn executable() -> common::TempArtifact {
    let repository = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = repository.join("sample_programs/library/range_dot.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(repository.join("stdlib")),
        user_roots: Vec::new(),
    };
    let bytes = common::run_gpu_codegen_with_timeout("range_dot application", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("range_dot: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_range_dot", "executable", None);
    // The existing shared writer applies the strict ELF/jump checker.
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
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
    // Aligning the '=' column can add spaces after ')'. Error annotations
    // also contain ')', so split at the result '=' and trim separately.
    let (arguments, result) = arguments
        .rsplit_once('=')
        .unwrap_or_else(|| panic!("missing syscall result: {line}"));
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
                assert!(
                    live.insert(address, length).is_none(),
                    "duplicate live mapping: {events}"
                );
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
            let owned_length = live
                .remove(&address)
                .unwrap_or_else(|| panic!("unknown/double release: {events}"));
            assert_eq!(length, owned_length, "{events}");
            trace.releases += 1;
        } else if line.starts_with("mremap(") {
            panic!("fixed argument snapshot must not grow storage: {events}");
        }
        // Signal and output events are checked separately from memory owners.
    }
    assert!(live.is_empty(), "unreleased owners {live:?}: {events}");
    assert_eq!(trace.releases, trace.successful, "{events}");
    trace
}

fn snapshot_profile(
    trace: &MemoryTrace,
    arguments: &[OsString],
    failed: Option<usize>,
    signal_ok: bool,
    events: &str,
) {
    let total: usize = arguments
        .iter()
        .map(|argument| argument.as_bytes().len())
        .sum();
    let normal_attempts = if !signal_ok || arguments.len() > 5 || total > 160 {
        0
    } else {
        usize::from(!arguments.is_empty()) + usize::from(total != 0)
    };
    if let Some(ordinal) = failed {
        assert!((1..=normal_attempts).contains(&ordinal));
        assert_eq!(trace.attempts, ordinal, "{events}");
        assert_eq!(trace.successful, ordinal - 1, "{events}");
        assert_eq!(trace.failed_ordinals, [ordinal], "{events}");
    } else {
        assert_eq!(trace.attempts, normal_attempts, "{events}");
        assert_eq!(trace.successful, normal_attempts, "{events}");
        assert!(trace.failed_ordinals.is_empty(), "{events}");
    }
    // One entry allocation and, when nonempty, one packed byte allocation.
    // Exact lengths are matched to each release without assuming View width.
}

fn policy(events: &str, successful: bool) {
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
    let (_, result) = syscall_result(action, "rt_sigaction");
    if successful {
        assert_eq!(result, "0", "{events}");
    } else {
        assert!(
            result.contains("EINTR") && result.contains("INJECTED"),
            "{events}"
        );
    }
    if let Some(next) = lines
        .iter()
        .position(|line| line.starts_with("mmap(") || line.starts_with("write("))
    {
        assert!(
            position < next,
            "SIGPIPE policy must precede allocation/output: {events}"
        );
    }
    assert!(
        calls(events, "read").is_empty(),
        "application does not read stdin: {events}"
    );
}

struct NativeRun {
    output: Output,
    events: String,
    memory: MemoryTrace,
}

fn run(
    executable: &common::TempArtifact,
    arguments: &[OsString],
    injections: &[&str],
    closed_stdout: bool,
) -> NativeRun {
    let trace = common::TempArtifact::new("laniusc_range_dot", "trace", None);
    // output() preserves a supplied closed pipe. The common capture helper
    // replaces stdout, so this explicit external timeout bounds that case.
    let mut command = Command::new("timeout");
    command
        .args(["--kill-after=1s", "5s", "strace", "-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=rt_sigaction,read,write,mmap,mremap,munmap",
            "-e",
            "signal=none",
        ]);
    for injection in injections {
        command.arg("-e").arg(format!("inject={injection}"));
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
    let output = command.output().expect("bounded range_dot native case");
    let events = fs::read_to_string(trace.path()).unwrap();
    for injection in injections {
        let syscall = injection.split(':').next().unwrap();
        let reached = calls(&events, syscall)
            .into_iter()
            .filter(|line| line.contains("INJECTED"))
            .collect::<Vec<_>>();
        assert_eq!(
            reached.len(),
            1,
            "unreached/repeated injection {injection}: {events}"
        );
        if let Some(tail) = injection.split("error=").nth(1) {
            assert!(
                reached[0].contains(tail.split(':').next().unwrap()),
                "{events}"
            );
        } else if let Some(tail) = injection.split("retval=").nth(1) {
            let expected = tail.split(':').next().unwrap();
            assert_eq!(
                syscall_result(reached[0], syscall)
                    .1
                    .split_whitespace()
                    .next()
                    .unwrap(),
                expected,
                "{events}"
            );
        }
    }
    if injections.is_empty() {
        assert!(!events.contains("INJECTED"), "{events}");
    }
    let memory = memory_trace(&events);
    NativeRun {
        output,
        events,
        memory,
    }
}

fn checked(
    result: &NativeRun,
    arguments: &[OsString],
    status: i32,
    stdout: &[u8],
    failed_map: Option<usize>,
    signal_ok: bool,
) {
    assert_eq!(
        result.output.status.code(),
        Some(status),
        "{arguments:?}: {:?}\n{}",
        result.output,
        result.events
    );
    assert_eq!(
        result.output.stdout, stdout,
        "{arguments:?}: {}",
        result.events
    );
    assert!(
        result.output.stderr.is_empty(),
        "{:?}\n{}",
        result.output,
        result.events
    );
    snapshot_profile(
        &result.memory,
        arguments,
        failed_map,
        signal_ok,
        &result.events,
    );
    policy(&result.events, signal_ok);
    for write in calls(&result.events, "write") {
        assert!(write.starts_with("write(1,"), "{}", result.events);
    }
}

fn no_write(result: &NativeRun) {
    assert!(
        calls(&result.events, "write").is_empty(),
        "{}",
        result.events
    );
}

// Closed-form sum of (a+k)(b+k) over k=0..n. All intermediates fit i128
// under i32 endpoint and million-quota bounds. Production walks adapters.
fn prefix_dot(a: i32, b: i32, count: u64) -> i128 {
    let a = i128::from(a);
    let b = i128::from(b);
    let n = i128::from(count);
    n * a * b + (a + b) * n * (n - 1) / 2 + n * (n - 1) * (2 * n - 1) / 6
}

#[derive(Debug)]
struct Reference {
    stdout: Vec<u8>,
    overflow_at: Option<u64>,
    final_dot: i128,
}

fn reference(
    left_start: i32,
    left_end: i32,
    right_start: i32,
    right_end: i32,
    limit: u64,
) -> Reference {
    let cardinality = |start: i32, end: i32| {
        if start > end {
            0
        } else {
            (i64::from(end) - i64::from(start) + 1) as u64
        }
    };
    let count = cardinality(left_start, left_end)
        .min(cardinality(right_start, right_end))
        .min(limit);
    let final_dot = prefix_dot(left_start, right_start, count);
    // Every prefix matters: a final value in range cannot undo prior overflow.
    let overflow_at = (1..=count).find(|&prefix| {
        !(i128::from(i64::MIN)..=i128::from(i64::MAX)).contains(&prefix_dot(
            left_start,
            right_start,
            prefix,
        ))
    });
    let stdout = if overflow_at.is_some() {
        Vec::new()
    } else {
        format!("count,dot\n{count},{final_dot}\n").into_bytes()
    };
    Reference {
        stdout,
        overflow_at,
        final_dot,
    }
}

fn numeric_arguments(
    left_start: i32,
    left_end: i32,
    right_start: i32,
    right_end: i32,
    limit: u64,
) -> Vec<OsString> {
    [
        left_start.to_string(),
        left_end.to_string(),
        right_start.to_string(),
        right_end.to_string(),
        limit.to_string(),
    ]
    .into_iter()
    .map(OsString::from)
    .collect()
}

#[test]
fn range_dot_csv_prefix_arithmetic_and_exact_failure_cleanup() {
    assert_eq!(reference(1, 5, 2, 6, 10).stdout, b"count,dot\n5,70\n");
    assert_eq!(reference(-2, 2, 3, 7, 5).stdout, b"count,dot\n5,10\n");
    // One production-root GPU compile and strict native check for every case.
    let executable = executable();
    let cases: &[(i32, i32, i32, i32, u64)] = &[
        (1, 5, 2, 6, 10),
        (-2, 2, 3, 7, 5),
        (i32::MIN, i32::MIN, i32::MIN, i32::MIN, 1),
        (i32::MAX, i32::MAX, i32::MAX, i32::MAX, 1),
        (i32::MIN, i32::MIN, i32::MAX, i32::MAX, 1),
        (i32::MAX, i32::MAX, i32::MIN, i32::MIN, 1),
        (i32::MAX - 1, i32::MAX, 1, 2, 10),
        (i32::MIN, i32::MIN + 1, -1, 0, 10),
        (i32::MIN, i32::MAX, 0, i32::MAX, 3),
        (9, 3, 1, 9, 5),
        (1, 9, 9, 3, 5),
        (1, 0, 1, 0, 5),
        (1, 3, 10, 15, 10),
        (1, 10, 10, 11, 10),
        (i32::MIN, i32::MAX, i32::MIN, i32::MAX, 0),
        (1, 9, 2, 10, 2),
        (0, 999_999, 0, 999_999, 1_000_000),
        (-999_999, 0, 0, 999_999, 1_000_000),
        (i32::MIN, i32::MIN + 2, i32::MIN, i32::MIN + 2, 2),
        (i32::MIN, i32::MIN + 2, i32::MIN, i32::MIN + 2, 3),
        (i32::MIN, i32::MIN + 2, i32::MAX - 2, i32::MAX, 2),
        (i32::MIN, i32::MIN + 2, i32::MAX - 2, i32::MAX, 3),
        (-500_000, 499_999, -2_000_000_000, -1_999_000_001, 1_000_000),
        (-500_000, 499_999, 2_000_000_000, 2_000_999_999, 1_000_000),
    ];
    for &(left_start, left_end, right_start, right_end, limit) in cases {
        let args = numeric_arguments(left_start, left_end, right_start, right_end, limit);
        let expected = reference(left_start, left_end, right_start, right_end, limit);
        let result = run(&executable, &args, &[], false);
        checked(
            &result,
            &args,
            if expected.overflow_at.is_some() { 5 } else { 0 },
            &expected.stdout,
            None,
            true,
        );
        if expected.overflow_at.is_some() {
            no_write(&result);
        }
    }
    for right_start in [-2_000_000_000, 2_000_000_000] {
        let witness = reference(
            -500_000,
            499_999,
            right_start,
            right_start + 999_999,
            1_000_000,
        );
        assert!(witness.overflow_at.is_some(), "{witness:?}");
        assert!(
            (i128::from(i64::MIN)..=i128::from(i64::MAX)).contains(&witness.final_dot),
            "cancellation witness must end in range: {witness:?}"
        );
    }
    assert_eq!(
        reference(i32::MIN, i32::MIN + 2, i32::MIN, i32::MIN + 2, 3).overflow_at,
        Some(3)
    );
    assert_eq!(
        reference(i32::MIN, i32::MIN + 2, i32::MAX - 2, i32::MAX, 3).overflow_at,
        Some(3)
    );

    let baseline = reference(-2, 2, 3, 7, 5).stdout;
    let signed_args = ["-0002", "+0002", "+0003", "0007", "0005"]
        .map(OsString::from)
        .to_vec();
    let fixed = ["-2", "2", "3", "7"];
    let fixed_bytes: usize = fixed.iter().map(|text| text.len()).sum();
    let mut budget_args = fixed.map(OsString::from).to_vec();
    budget_args.push(format!("{}5", "0".repeat(160 - fixed_bytes - 1)).into());
    assert_eq!(
        budget_args
            .iter()
            .map(|text| text.as_bytes().len())
            .sum::<usize>(),
        160
    );
    for args in [signed_args, budget_args] {
        let result = run(&executable, &args, &[], false);
        checked(&result, &args, 0, &baseline, None, true);
    }

    let valid = numeric_arguments(-2, 2, 3, 7, 5);
    let mut invalid = (0..5)
        .map(|length| valid[..length].to_vec())
        .collect::<Vec<_>>();
    let mut extra = valid.clone();
    extra.push("extra".into());
    invalid.push(extra);
    invalid.push(vec![OsString::new(); 5]);
    for index in 0..4 {
        for text in ["2147483648", "-2147483649"] {
            let mut args = valid.clone();
            args[index] = text.into();
            invalid.push(args);
        }
    }
    for text in ["", "+", "-", " 1", "1 ", "1x", "1.0", "١"] {
        let mut args = valid.clone();
        args[0] = text.into();
        invalid.push(args);
    }
    for text in [
        "",
        "+1",
        "-1",
        "1000001",
        "18446744073709551615",
        "18446744073709551616",
        "1\n",
    ] {
        let mut args = valid.clone();
        args[4] = text.into();
        invalid.push(args);
    }
    let mut raw = valid.clone();
    raw[2] = OsString::from_vec(vec![255]);
    invalid.push(raw);
    let mut over_budget = valid.clone();
    over_budget[4] = "0".repeat(161).into();
    invalid.push(over_budget);
    assert_eq!(invalid.len(), 32);
    for args in invalid {
        let result = run(&executable, &args, &[], false);
        checked(&result, &args, 2, b"", None, true);
        no_write(&result);
    }

    for ordinal in 1..=2 {
        let injection = format!("mmap:error=ENOMEM:when={ordinal}");
        let result = run(&executable, &valid, &[&injection], false);
        checked(&result, &valid, 4, b"", Some(ordinal), true);
        no_write(&result);
    }

    for (injection, status, stdout, writes) in [
        ("write:error=EIO:when=1", 3, b"".as_slice(), 1),
        ("write:error=EAGAIN:when=1", 3, b"".as_slice(), 1),
        ("write:retval=0:when=1", 3, b"".as_slice(), 1),
        ("write:error=EINTR:when=1", 0, baseline.as_slice(), 2),
        ("write:retval=1:when=1", 0, &baseline[1..], 2),
    ] {
        let result = run(&executable, &valid, &[injection], false);
        checked(&result, &valid, status, stdout, None, true);
        let observed = calls(&result.events, "write");
        assert_eq!(observed.len(), writes, "{}", result.events);
        if injection.contains("retval=1") {
            // strace reports one byte written while suppressing that syscall.
            // The actual stdout must be the remaining suffix exactly once.
            let (resumed, _) = syscall_result(observed[1], "write");
            assert_eq!(
                resumed
                    .rsplit_once(',')
                    .unwrap()
                    .1
                    .trim()
                    .parse::<usize>()
                    .unwrap(),
                baseline.len() - 1,
                "{}",
                result.events
            );
        }
    }
    let result = run(&executable, &valid, &[], true);
    checked(&result, &valid, 3, b"", None, true);
    let writes = calls(&result.events, "write");
    assert_eq!(writes.len(), 1, "{}", result.events);
    assert!(
        writes[0].contains("EPIPE") && !writes[0].contains("INJECTED"),
        "{}",
        result.events
    );

    let result = run(
        &executable,
        &valid,
        &["rt_sigaction:error=EINTR:when=1"],
        false,
    );
    checked(&result, &valid, 3, b"", None, false);
    no_write(&result);
}
