//! Finite native seek-state and allocation-effect witnesses for buffered streams.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_foundation/buffered_seek");
    let entry = fixtures.join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixtures],
    };
    let label = format!("buffered seek {name}");
    let bytes = common::run_gpu_codegen_with_timeout(&label, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("buffered seek {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_buffered_seek", name, None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}

#[derive(Debug)]
struct Profile {
    attempts: Vec<usize>,
    successful: Vec<usize>,
    releases: Vec<usize>,
    // One-based allocation attempts, not merely an observed failure exit.
    failures: Vec<(usize, usize)>,
}

fn fields<'a>(arguments: &'a str, events: &str) -> (&'a str, &'a str) {
    let (arguments, tail) = arguments
        .split_once(')')
        .unwrap_or_else(|| panic!("missing argument terminator: {events}"));
    let result = tail
        .trim_start()
        .strip_prefix('=')
        .unwrap_or_else(|| panic!("missing result separator: {events}"));
    (arguments, result.trim())
}

// Local ledger for fixed u8 buffers. Every actual host call is observed; the
// scripted peer has no host service, and no host call is permitted inside P/p.
fn observed(events: &str, phases: usize, expected_exit: i32) -> Profile {
    let mut profile = Profile {
        attempts: Vec::new(),
        successful: Vec::new(),
        releases: Vec::new(),
        failures: Vec::new(),
    };
    let mut live = BTreeMap::<String, (usize, usize)>::new();
    let mut pure = false;
    let mut completed = 0;
    let mut done = false;
    let mut executions = 0;
    let mut exits = 0;
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert_eq!(line.rsplit_once('=').unwrap().1.trim(), "1", "{events}");
            if line.contains("\"P\", 1)") {
                assert!(!pure && !done, "{events}");
                pure = true;
            } else if line.contains("\"p\", 1)") {
                assert!(pure && !done, "{events}");
                pure = false;
                completed += 1;
            } else {
                assert!(line.contains("\"D\", 1)"), "{events}");
                assert!(!pure && !done && live.is_empty(), "{events}");
                done = true;
            }
            continue;
        }
        assert!(
            !pure,
            "host call during buffered seek phase: {line}\n{events}"
        );
        if line.starts_with(&format!("exit({expected_exit})"))
            || line.starts_with(&format!("exit_group({expected_exit})"))
        {
            assert!(done, "{events}");
            exits += 1;
            continue;
        }
        assert!(!done, "only process exit follows cleanup: {events}");
        if line.starts_with("execve(") {
            assert!(
                executions == 0 && completed == 0 && live.is_empty(),
                "{events}"
            );
            assert_eq!(line.rsplit_once('=').unwrap().1.trim(), "0", "{events}");
            executions += 1;
        } else if let Some(arguments) = line.strip_prefix("mmap(") {
            let (arguments, result) = fields(arguments, events);
            let mut arguments = arguments.split(',');
            assert_eq!(arguments.next().unwrap().trim(), "NULL", "{events}");
            let size: usize = arguments.next().unwrap().trim().parse().unwrap();
            assert!(size > 0, "{events}");
            profile.attempts.push(size);
            let address = result.split_whitespace().next().unwrap();
            if address.starts_with("0x") {
                assert!(!result.contains("INJECTED"), "{events}");
                let id = profile.successful.len();
                assert!(
                    live.insert(address.to_owned(), (id, size)).is_none(),
                    "{events}"
                );
                profile.successful.push(size);
            } else {
                assert_eq!(address, "-1", "{events}");
                assert!(
                    result.contains("ENOMEM") && result.contains("INJECTED"),
                    "{events}"
                );
                profile.failures.push((profile.attempts.len(), size));
            }
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = fields(arguments, events);
            assert_eq!(result, "0", "{events}");
            let (address, size) = arguments.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            let (id, owned_size) = live
                .remove(address.trim())
                .unwrap_or_else(|| panic!("unknown or repeated buffer release: {events}"));
            assert_eq!(size, owned_size, "{events}");
            profile.releases.push(id);
        } else {
            panic!("unexpected host call in scripted buffered seek fixture: {line}\n{events}");
        }
    }
    assert!(!pure && done && live.is_empty(), "{events}");
    assert_eq!((executions, exits, completed), (1, 1, phases), "{events}");
    profile
}

fn run(file: &common::TempArtifact, fault: Option<usize>, phases: usize) -> Profile {
    let trace = common::TempArtifact::new("laniusc_buffered_seek", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=all", "-e", "signal=none"]);
    if let Some(ordinal) = fault {
        command
            .arg("-e")
            .arg(format!("inject=mmap:error=ENOMEM:when={ordinal}"));
    }
    command.arg(file.path());
    let output =
        common::short_process_output_with_timeout("buffered seek scripted lifecycle", &mut command);
    let events = fs::read_to_string(trace.path()).unwrap();
    let exit = if fault.is_some() { 2 } else { 0 };
    assert_eq!(output.status.code(), Some(exit), "{output:?}\n{events}");
    assert!(output.stdout.is_empty(), "{output:?}\n{events}");
    let mut markers = b"Pp".repeat(phases);
    markers.push(b'D');
    assert_eq!(output.stderr, markers, "{output:?}\n{events}");
    observed(&events, phases, exit)
}

fn exact(
    profile: &Profile,
    attempts: &[usize],
    successful: &[usize],
    releases: &[usize],
    failures: &[(usize, usize)],
) {
    assert_eq!(profile.attempts, attempts, "{profile:?}");
    assert_eq!(profile.successful, successful, "{profile:?}");
    assert_eq!(profile.releases, releases, "{profile:?}");
    assert_eq!(profile.failures, failures, "{profile:?}");
}

#[test]
fn reader_seek_reconciles_read_ahead_and_distinguishes_arithmetic_from_provider_failure() {
    let file = executable("reader");
    let profile = run(&file, None, 9);
    let sizes = [4; 9];
    exact(&profile, &sizes, &sizes, &(0..9).collect::<Vec<_>>(), &[]);
}

#[test]
fn writer_seek_orders_complete_flush_and_preserves_partial_or_faulted_progress() {
    let file = executable("writer");
    let profile = run(&file, None, 12);
    let sizes = [4, 4, 4, 4, 4, 4, 4, 4, 3, 3, 3, 2];
    exact(&profile, &sizes, &sizes, &(0..12).collect::<Vec<_>>(), &[]);
}

#[test]
fn nested_seek_transfers_real_buffer_authority_and_reaches_each_constructor_denial() {
    let file = executable("nesting");
    let sizes = [3, 3, 4, 5];
    let baseline = run(&file, None, 1);
    exact(&baseline, &sizes, &sizes, &[3, 2, 1, 0], &[]);
    for ordinal in 1..=4 {
        let profile = run(&file, Some(ordinal), 0);
        let releases = (0..ordinal - 1).rev().collect::<Vec<_>>();
        exact(
            &profile,
            &sizes[..ordinal],
            &sizes[..ordinal - 1],
            &releases,
            &[(ordinal, sizes[ordinal - 1])],
        );
    }
}
