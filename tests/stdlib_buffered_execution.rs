//! Native x86_64 Linux admission gates for buffered streams and binary copy.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output},
};

fn executable_entry(entry: PathBuf, user_roots: Vec<PathBuf>, name: &str) -> common::TempArtifact {
    let repository = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(repository.join("stdlib")),
        user_roots,
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("buffered {name}: {error}"));
    let executable = common::TempArtifact::new("laniusc_buffered", name, None);
    // Existing TempArtifact applies the strict shared x86 ELF/jump checker.
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn executable(name: &str) -> common::TempArtifact {
    let repository = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixtures = repository.join("tests/fixtures/stdlib_foundation/buffered");
    executable_entry(fixtures.join(format!("{name}.lani")), vec![fixtures], name)
}

#[derive(Debug)]
struct Trace {
    text: String,
    attempt_lengths: Vec<usize>,
    successful_lengths: Vec<usize>,
    // (one-based mmap attempt ordinal, requested length)
    failures: Vec<(usize, usize)>,
    // Zero-based successful-allocation identities, not just sizes. Addresses
    // may be reused only after their prior owner was released.
    release_ids: Vec<usize>,
}

fn syscall_result<'a>(arguments: &'a str, line: &str, events: &str) -> (&'a str, &'a str) {
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

fn memory_trace(text: String) -> Trace {
    let mut live = BTreeMap::<String, (usize, usize)>::new();
    let mut trace = Trace {
        text,
        attempt_lengths: Vec::new(),
        successful_lengths: Vec::new(),
        failures: Vec::new(),
        release_ids: Vec::new(),
    };
    for line in trace.text.lines() {
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let (arguments, result) = syscall_result(arguments, line, &trace.text);
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
            let (arguments, result) = syscall_result(arguments, line, &trace.text);
            assert_eq!(result.trim(), "0", "{}", trace.text);
            let (address, length) = arguments.split_once(',').unwrap();
            let length: usize = length.trim().parse().unwrap();
            let (id, owned_length) = live.remove(address.trim()).unwrap_or_else(|| {
                panic!("release of unknown/already released owner: {}", trace.text)
            });
            assert_eq!(length, owned_length, "{}", trace.text);
            trace.release_ids.push(id);
        } else {
            // Includes mremap: these adapters must never grow or relocate.
            panic!("unexpected memory event: {}", trace.text);
        }
    }
    assert!(live.is_empty(), "unreleased owners: {}", trace.text);
    trace
}

fn run(executable: &common::TempArtifact, fault: Option<usize>, expected_exit: i32) -> Trace {
    let trace = common::TempArtifact::new("laniusc_buffered", "memory_trace", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,mremap,munmap"]);
    if let Some(ordinal) = fault {
        command
            .arg("-e")
            .arg(format!("inject=mmap:error=ENOMEM:when={ordinal}"));
    }
    let output = common::short_process_output_with_timeout(
        "buffered byte streams",
        command.arg(executable.path()),
    );
    assert_eq!(output.status.code(), Some(expected_exit), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    memory_trace(fs::read_to_string(trace.path()).expect("read buffered memory trace"))
}

fn exact_profile(
    trace: &Trace,
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

#[test]
fn reader_preserves_logical_bytes_handoff_and_fault_state() {
    let executable = executable("reader");
    let trace = run(&executable, None, 0);
    let sizes = [4, 2, 2, 2, 2];
    exact_profile(&trace, &sizes, &sizes, &[0, 1, 2, 3, 4], &[]);
}

#[test]
fn writer_preserves_current_acceptance_pending_offsets_and_inner_flush() {
    let executable = executable("writer");
    let trace = run(&executable, None, 0);
    let sizes = [4, 1, 1, 2, 2, 2, 2, 2, 2];
    exact_profile(&trace, &sizes, &sizes, &[0, 1, 2, 3, 4, 5, 6, 7, 8], &[]);
}

#[test]
fn imported_nested_readers_and_writers_compose_through_copy() {
    let executable = executable("composition");
    let trace = run(&executable, None, 0);
    let sizes = [7, 3, 2, 3, 2];
    exact_profile(&trace, &sizes, &sizes, &[4, 3, 2, 1, 0], &[]);
}

#[test]
fn each_of_four_construction_failures_releases_exact_preceding_owners() {
    // Current Linux x86 source path, not a page-rounding guess:
    // core::mem::size_of<u8>() is 1; Vec::relocate calls alloc(capacity,8).
    // shaders/codegen/lir/x86/runtime_abi.slang alloc_bytes forwards that size
    // unchanged into mmap's length argument; dealloc forwards the same length
    // to munmap. Kernel page granularity does not change these traced args.
    let executable = executable("allocation");
    let sizes = [2, 3, 4, 5];
    let baseline = run(&executable, None, 0);
    exact_profile(&baseline, &sizes, &sizes, &[3, 2, 1, 0], &[]);
    for ordinal in 1..=4 {
        let trace = run(&executable, Some(ordinal), 2);
        let releases = (0..ordinal - 1).rev().collect::<Vec<_>>();
        exact_profile(
            &trace,
            &sizes[..ordinal],
            &sizes[..ordinal - 1],
            &releases,
            &[(ordinal, sizes[ordinal - 1])],
        );
    }
}

fn sample_run(
    executable: &common::TempArtifact,
    input: &[u8],
    allocation_failure: Option<usize>,
    closed_stdout: bool,
) -> (Output, String, Trace) {
    let source = common::TempArtifact::new("laniusc_buffered", "copy_input", None);
    source.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_buffered", "copy_trace", None);
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
    if let Some(ordinal) = allocation_failure {
        command
            .arg("-e")
            .arg(format!("inject=mmap:error=ENOMEM:when={ordinal}"));
    }
    command
        .arg(executable.path())
        .stdin(fs::File::open(source.path()).unwrap());
    if closed_stdout {
        let (reader, writer) = std::io::pipe().unwrap();
        drop(reader);
        command.stdout(writer);
    }
    // Existing closed-pipe gate pattern: Command::output retains an explicit
    // stdout redirection. The common capturing helper would replace it and
    // would test a readable capture pipe instead. GNU timeout bounds this
    // standard output call; no custom process/wait runner is introduced.
    let output = command.output().expect("bounded buffered copy sample");
    let events = fs::read_to_string(trace.path()).expect("read buffered copy trace");
    let memory_events = events
        .lines()
        .filter(|line| {
            line.starts_with("mmap(") || line.starts_with("mremap(") || line.starts_with("munmap(")
        })
        .collect::<Vec<_>>()
        .join("\n");
    let memory = memory_trace(memory_events);
    (output, events, memory)
}

fn signal_policy_precedes_buffers(events: &str) {
    let lines = events.lines().collect::<Vec<_>>();
    let signals = lines
        .iter()
        .enumerate()
        .filter(|(_, line)| line.starts_with("rt_sigaction("))
        .collect::<Vec<_>>();
    assert_eq!(signals.len(), 1, "{events}");
    let (position, signal) = signals[0];
    assert!(
        signal.contains("SIGPIPE") && signal.contains("SIG_IGN") && signal.ends_with(" = 0"),
        "{events}"
    );
    let first_allocation = lines
        .iter()
        .position(|line| line.starts_with("mmap("))
        .expect("sample must attempt buffer construction");
    assert!(position < first_allocation, "{events}");
}

#[test]
fn binary_copy_sample_finishes_and_releases_buffers_on_pipe_and_allocation_errors() {
    let repository = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    // One GPU compile supplies every ordinary/fault native sample case.
    let executable = executable_entry(
        repository.join("sample_programs/library/buffered_copy.lani"),
        Vec::new(),
        "buffered_copy",
    );
    for length in [0, 1, 4095, 4096, 4097, 10000] {
        let input = (0..length)
            .map(|index| {
                (index as u8)
                    .wrapping_mul(73)
                    .wrapping_add((index >> 8) as u8)
            })
            .collect::<Vec<_>>();
        let (output, events, trace) = sample_run(&executable, &input, None, false);
        assert_eq!(
            output.status.code(),
            Some(0),
            "{length}: {output:?}\n{events}"
        );
        assert_eq!(output.stdout, input, "{length}: {events}");
        assert!(output.stderr.is_empty(), "{output:?}");
        signal_policy_precedes_buffers(&events);
        exact_profile(&trace, &[4096, 4096], &[4096, 4096], &[1, 0], &[]);
    }
    let input = vec![0x80, 0, 0xff, 10].repeat(2500);
    for ordinal in 1..=2 {
        let (output, events, trace) = sample_run(&executable, &input, Some(ordinal), false);
        assert_eq!(output.status.code(), Some(4), "{output:?}\n{events}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        signal_policy_precedes_buffers(&events);
        assert!(
            !events
                .lines()
                .any(|line| line.starts_with("read(") || line.starts_with("write(")),
            "failed construction must precede input/output: {events}"
        );
        let sizes = [4096, 4096];
        let releases = (0..ordinal - 1).rev().collect::<Vec<_>>();
        exact_profile(
            &trace,
            &sizes[..ordinal],
            &sizes[..ordinal - 1],
            &releases,
            &[(ordinal, 4096)],
        );
    }
    // One byte reaches EPIPE in finish; 10000 reaches it in copy's drain.
    for length in [1, 10000] {
        let (output, events, trace) = sample_run(&executable, &input[..length], None, true);
        assert_eq!(
            output.status.code(),
            Some(3),
            "{length}: {output:?}\n{events}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        signal_policy_precedes_buffers(&events);
        assert!(
            events
                .lines()
                .any(|line| line.starts_with("write(1,") && line.contains("EPIPE")),
            "closed-pipe gate must reach the actual stdout error: {events}"
        );
        exact_profile(&trace, &[4096, 4096], &[4096, 4096], &[1, 0], &[]);
    }
}
