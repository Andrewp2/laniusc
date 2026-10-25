#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_poll", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn two_native_pollfd_records_have_the_checked_stride() {
    let exe = executable("poll_admission");
    let out = common::process_output_with_timeout(
        "poll layout admission",
        &mut Command::new(exe.path()),
        Duration::from_secs(5),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stdout.is_empty() && out.stderr.is_empty(), "{out:?}");
}

#[test]
fn readiness_is_ordered_borrowed_and_preserves_pipe_and_socket_events() {
    let exe = executable("poll_contracts");
    let out = common::process_output_with_timeout(
        "poll contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(5),
    );
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stdout.is_empty() && out.stderr.is_empty(), "{out:?}");
}

fn checked(out: &Output, code: i32) {
    assert_eq!(out.status.code(), Some(code), "{out:?}");
    assert!(out.stdout.is_empty() && out.stderr.is_empty(), "{out:?}");
}
fn timespec_hex(seconds: i64, nanos: i64) -> String {
    seconds
        .to_le_bytes()
        .into_iter()
        .chain(nanos.to_le_bytes())
        .map(|byte| format!("{byte:02x}"))
        .collect()
}
fn trace_run(exe: &common::TempArtifact, mode: u8, faults: &[String]) -> (Output, String) {
    let trace = common::TempArtifact::new("laniusc_poll", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap,poll,clock_gettime,close"]);
    for fault in faults {
        command.arg("-e").arg(format!("inject={fault}"));
    }
    let out = common::process_output_with_timeout(
        "poll fault contract",
        command.arg(exe.path()).arg(mode.to_string()),
        Duration::from_secs(5),
    );
    (out, std::fs::read_to_string(trace.path()).unwrap())
}
fn attempts(trace: &str, syscall: &str) -> usize {
    trace
        .lines()
        .filter(|line| line.starts_with(syscall))
        .count()
}
fn poll_timeouts(trace: &str) -> Vec<i32> {
    trace
        .lines()
        .filter(|line| line.starts_with("poll("))
        .map(|line| {
            line.split_once(')')
                .unwrap()
                .0
                .rsplit(", ")
                .next()
                .unwrap()
                .parse()
                .unwrap()
        })
        .collect()
}
fn assert_allocations_released(trace: &str) {
    let mut live = std::collections::BTreeMap::new();
    for line in trace.lines() {
        if line.starts_with("mmap(") && !line.contains(" = -1 ") {
            let arguments = line.split_once('(').unwrap().1;
            let size = arguments
                .split(',')
                .nth(1)
                .unwrap()
                .trim()
                .parse::<usize>()
                .unwrap();
            let address = line
                .split_once(" = ")
                .unwrap()
                .1
                .split_whitespace()
                .next()
                .unwrap();
            assert!(live.insert(address.to_owned(), size).is_none(), "{trace}");
        }
        if let Some(rest) = line.strip_prefix("munmap(") {
            let (address, rest) = rest.split_once(',').unwrap();
            let size = rest
                .split_once(')')
                .unwrap()
                .0
                .trim()
                .parse::<usize>()
                .unwrap();
            assert_eq!(live.remove(address), Some(size), "{trace}");
            assert!(line.contains(" = 0"), "{trace}");
        }
    }
    assert!(live.is_empty(), "{trace}");
}

#[test]
fn poll_errors_and_malformed_kernel_results_preserve_publication_and_cleanup() {
    let exe = executable("poll_fault");
    let (out, baseline) = trace_run(&exe, 0, &[]);
    checked(&out, 0);
    assert_eq!(attempts(&baseline, "mmap("), 2, "{baseline}");
    assert_eq!(attempts(&baseline, "poll("), 2, "{baseline}");
    assert_eq!(
        attempts(&baseline, "close("),
        0,
        "borrowed descriptors: {baseline}"
    );
    assert_allocations_released(&baseline);
    for allocation in 1..=2 {
        let (out, trace) = trace_run(&exe, 0, &[format!("mmap:error=ENOMEM:when={allocation}")]);
        checked(&out, 53);
        assert_eq!(attempts(&trace, "poll("), 0, "{trace}");
        assert_allocations_released(&trace);
    }
    for (fault, code) in [
        ("poll:error=EINTR:when=2", 104),
        ("poll:error=EAGAIN:when=2", 111),
        ("poll:error=ENOMEM:when=2", 112),
        ("poll:error=EINVAL:when=2", 122),
        ("poll:retval=2:when=2", 51),
        ("poll:retval=1:when=2", 51),
        ("poll:retval=0:poke_exit=@arg1=0100000004000400:when=2", 51),
        ("poll:retval=1:poke_exit=@arg1=0200000004000400:when=2", 51),
        ("poll:retval=1:poke_exit=@arg1=0100000001000400:when=2", 51),
    ] {
        let (out, trace) = trace_run(&exe, 0, &[fault.into()]);
        checked(&out, code);
        assert_eq!(attempts(&trace, "poll("), 2, "{fault}: {trace}");
        assert_allocations_released(&trace);
    }
    let (out, trace) = trace_run(
        &exe,
        5,
        &["poll:retval=1:poke_exit=@arg1=ffffffff04000400:when=2".into()],
    );
    checked(&out, 51);
    assert_allocations_released(&trace);
    let (out, trace) = trace_run(
        &exe,
        6,
        &["poll:retval=1:poke_exit=@arg1=0100000004000080:when=2".into()],
    );
    checked(&out, 0);
    assert_allocations_released(&trace);
}

#[test]
fn absolute_deadlines_check_late_readiness_clock_faults_and_actual_attempts() {
    let exe = executable("poll_fault");
    let (out, trace) = trace_run(&exe, 2, &[]);
    checked(&out, 0);
    assert_eq!(
        attempts(&trace, "poll("),
        1,
        "initially expired makes no attempt: {trace}"
    );
    assert_eq!(attempts(&trace, "clock_gettime("), 1, "{trace}");
    assert_allocations_released(&trace);
    let (out, trace) = trace_run(
        &exe,
        1,
        &[format!(
            "clock_gettime:retval=0:poke_exit=@arg2={}:when=1",
            timespec_hex(0, 0)
        )],
    );
    checked(&out, 0);
    assert_eq!(
        poll_timeouts(&trace),
        [0, 1],
        "ceil one nanosecond then discard late readiness: {trace}"
    );
    assert_eq!(attempts(&trace, "clock_gettime("), 2, "{trace}");
    assert_allocations_released(&trace);
    let (out, trace) = trace_run(&exe, 4, &[]);
    checked(&out, 0);
    assert_eq!(
        poll_timeouts(&trace),
        [0, i32::MAX],
        "clamped timeout: {trace}"
    );
    assert_allocations_released(&trace);
    for (fault, code, polls) in [
        ("clock_gettime:error=EINTR:when=1".to_owned(), 154, 1),
        ("clock_gettime:error=EIO:when=2".to_owned(), 155, 2),
        ("clock_gettime:error=EINTR:when=2".to_owned(), 154, 2),
        (
            format!(
                "clock_gettime:retval=0:poke_exit=@arg2={}:when=2",
                timespec_hex(1, 1_000_000_000)
            ),
            148,
            2,
        ),
        (
            format!(
                "clock_gettime:retval=0:poke_exit=@arg2={}:when=1",
                timespec_hex(i64::MAX, 0)
            ),
            149,
            2,
        ),
        ("poll:error=EAGAIN:when=2".to_owned(), 111, 2),
    ] {
        let (out, trace) = trace_run(&exe, 7, &[fault]);
        checked(&out, code);
        assert_eq!(attempts(&trace, "poll("), polls, "{trace}");
        assert_allocations_released(&trace);
    }
    let (out, trace) = trace_run(&exe, 7, &["poll:error=EINTR:when=2".into()]);
    checked(&out, 0);
    assert_eq!(attempts(&trace, "poll("), 3, "one retry: {trace}");
    assert_eq!(attempts(&trace, "clock_gettime("), 3, "{trace}");
    assert_allocations_released(&trace);
    let (out, trace) = trace_run(&exe, 4, &["poll:error=EINTR:when=2+".into()]);
    checked(&out, 50);
    assert_eq!(
        attempts(&trace, "poll("),
        2,
        "one actual attempt incl EINTR: {trace}"
    );
    assert_allocations_released(&trace);
    let (out, trace) = trace_run(&exe, 8, &["poll:retval=0:when=2+".into()]);
    checked(&out, 50);
    assert_eq!(
        attempts(&trace, "poll("),
        3,
        "two zero-ready attempts then limit: {trace}"
    );
    assert_allocations_released(&trace);
    let (out, trace) = trace_run(&exe, 9, &["poll:error=EINTR:delay_exit=50ms:when=2".into()]);
    checked(&out, 0);
    let timeouts: Vec<i32> = poll_timeouts(&trace).into_iter().skip(1).collect();
    assert_eq!(timeouts.len(), 2, "{trace}");
    assert!(
        timeouts[0] > timeouts[1] && timeouts[1] > 0,
        "absolute deadline recomputed after EINTR: {trace}"
    );
    assert_allocations_released(&trace);
}

#[test]
fn readiness_matches_independent_os_poll_for_raw_handles_and_many_records() {
    let exe = executable("poll_oracle");
    let oracle = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/poll_oracle.py");
    let out = common::process_output_with_timeout(
        "independent poll oracle",
        Command::new("python3").arg(oracle).arg(exe.path()),
        Duration::from_secs(15),
    );
    checked(&out, 0);
}
