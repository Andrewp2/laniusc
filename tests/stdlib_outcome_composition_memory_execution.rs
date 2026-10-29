//! Finite real-owner and effect witnesses for eager outcome composition.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::{Duration, Instant},
};

fn executable() -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/outcome_composition_memory/owners.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("outcome composition owners", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("outcome composition owners: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_outcome_memory", "owners", None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}

// Local witness for these six String+Vec records, not a general owner checker.
fn observed_effects(events: &str) {
    let mut pure = false;
    let mut phases = 0;
    let mut finished = false;
    let mut live = BTreeMap::<String, usize>::new();
    let mut allocations = 0;
    let mut releases = 0;
    let mut executions = 0;
    let mut exits = 0;
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert_eq!(line.rsplit_once('=').unwrap().1.trim(), "1", "{events}");
            if line.contains("\"P\", 1)") {
                assert!(!pure && !finished, "{events}");
                pure = true;
            } else if line.contains("\"p\", 1)") {
                assert!(pure && !finished, "{events}");
                pure = false;
                phases += 1;
            } else {
                assert!(line.contains("\"D\", 1)"), "{events}");
                assert!(
                    !pure && !finished && live.is_empty(),
                    "all actual owners retired before D: {events}"
                );
                finished = true;
            }
            continue;
        }
        assert!(
            !pure,
            "no host call inside outcome conversion/check phase: {line}"
        );
        if line.starts_with("exit_group(0)") || line.starts_with("exit(0)") {
            assert!(finished, "{events}");
            exits += 1;
            continue;
        }
        assert!(
            !finished,
            "only process exit follows final cleanup: {events}"
        );
        if line.starts_with("execve(") {
            assert!(allocations == 0 && phases == 0, "{events}");
            executions += 1;
            assert_eq!(line.rsplit_once('=').unwrap().1.trim(), "0", "{events}");
        } else if let Some(arguments) = line.strip_prefix("mmap(") {
            assert_eq!(
                phases, 0,
                "all actual owners created before conversions: {events}"
            );
            let size: usize = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let result = line.rsplit_once('=').unwrap().1.trim();
            let address = result.split_whitespace().next().unwrap();
            assert!(address.starts_with("0x") && size > 0, "{events}");
            assert!(
                live.insert(address.to_owned(), size).is_none(),
                "unique actual backing: {events}"
            );
            allocations += 1;
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            assert_eq!(
                phases, 7,
                "every selected/discarded payload remains live through conversions: {events}"
            );
            let (arguments, _) = arguments.split_once(')').unwrap();
            let (address, size) = arguments.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            assert_eq!(
                live.remove(address.trim()),
                Some(size),
                "one exact release per actual owner: {events}"
            );
            assert_eq!(line.rsplit_once('=').unwrap().1.trim(), "0", "{events}");
            releases += 1;
        } else {
            panic!("unexpected host service: {line}");
        }
    }
    assert!(finished && !pure && live.is_empty(), "{events}");
    assert_eq!(
        (executions, exits, allocations, releases, phases),
        (1, 1, 12, 12, 7),
        "{events}"
    );
}

#[test]
fn outcome_composition_keeps_real_owner_identity_and_cleanup_without_phase_host_calls() {
    let executable = executable();
    let trace = common::TempArtifact::new("laniusc_outcome_memory", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=all", "-e", "signal=none"])
        .arg(executable.path());
    let started = Instant::now();
    let output = common::process_output_with_timeout(
        "outcome composition owned lifecycle",
        &mut command,
        Duration::from_secs(30),
    );
    let elapsed = started.elapsed();
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    assert!(output.stdout.is_empty(), "{output:?}");
    assert_eq!(output.stderr, b"PpPpPpPpPpPpPpD", "{output:?}\n{events}");
    observed_effects(&events);
    eprintln!(
        "outcome-composition actual_records=6 actual_backings=12 pure_phases=7 instrumented_whole_lifecycle_ms={}",
        elapsed.as_millis()
    );
}
