//! Exact native endian memory/effect witnesses and a bounded record scale gate.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::{Duration, Instant},
};

fn executable(fixture: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!(
        "tests/fixtures/stdlib_foundation/native_endian_memory/{fixture}.lani"
    ));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("native endian memory/effects", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("native endian {fixture}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_endian_memory", fixture, None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}

fn observed_effects(events: &str, expected_phases: usize, expected_bytes: usize, report: bool) {
    let mut pure = false;
    let mut phases = 0;
    let mut finished = false;
    let mut mapping: Option<(String, usize)> = None;
    let mut allocations = 0;
    let mut releases = 0;
    let mut executions = 0;
    let mut exits = 0;
    let mut reports = 0;
    for line in events.lines() {
        if line.starts_with("write(2,") {
            let result = line.rsplit_once('=').unwrap().1.trim();
            assert_eq!(result, "1", "{events}");
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
                    !pure && !finished && mapping.is_none(),
                    "explicit cleanup before D: {events}"
                );
                finished = true;
            }
            continue;
        }
        assert!(
            !pure,
            "no host call of any kind inside endian phase: {line}"
        );
        if line.starts_with("exit_group(0)") || line.starts_with("exit(0)") {
            assert!(finished, "exit after cleanup marker: {events}");
            exits += 1;
            continue;
        }
        assert!(
            !finished,
            "only process exit may follow cleanup marker: {events}"
        );
        if line.starts_with("execve(") {
            assert!(allocations == 0 && phases == 0, "{events}");
            executions += 1;
            assert_eq!(line.rsplit_once('=').unwrap().1.trim(), "0", "{events}");
        } else if let Some(arguments) = line.strip_prefix("mmap(") {
            assert!(
                mapping.is_none() && allocations == 0 && phases == 0,
                "one source backing before phases: {events}"
            );
            let bytes: usize = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let result = line.rsplit_once('=').unwrap().1.trim();
            let address = result.split_whitespace().next().unwrap();
            assert!(address.starts_with("0x"), "successful backing: {events}");
            assert_eq!(bytes, expected_bytes, "{events}");
            mapping = Some((address.to_owned(), bytes));
            allocations += 1;
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            assert_eq!(
                phases, expected_phases,
                "backing stays live through all phases: {events}"
            );
            let (arguments, _) = arguments.split_once(')').unwrap();
            let (address, size) = arguments.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            assert_eq!(
                mapping.take(),
                Some((address.trim().to_owned(), size)),
                "one exact backing release: {events}"
            );
            assert_eq!(line.rsplit_once('=').unwrap().1.trim(), "0", "{events}");
            releases += 1;
        } else if line.starts_with("write(1,") {
            assert!(
                report && phases == expected_phases && line.contains(", 12)"),
                "count report outside pure phase: {events}"
            );
            assert_eq!(line.rsplit_once('=').unwrap().1.trim(), "12", "{events}");
            reports += 1;
        } else {
            panic!("unexpected host service: {line}");
        }
    }
    assert!(finished && !pure && mapping.is_none(), "{events}");
    assert_eq!(
        (executions, exits, allocations, releases, phases, reports),
        (1, 1, 1, 1, expected_phases, usize::from(report)),
        "{events}"
    );
}

fn run(fixture: &str, phases: usize, bytes: usize, report: bool) -> Vec<u8> {
    let executable = executable(fixture);
    let trace = common::TempArtifact::new("laniusc_endian_memory", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=all", "-e", "signal=none"])
        .arg(executable.path());
    let started = Instant::now();
    let output = common::process_output_with_timeout(
        "native endian memory lifecycle",
        &mut command,
        Duration::from_secs(30),
    );
    let elapsed = started.elapsed();
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    let mut expected = b"Pp".repeat(phases);
    expected.push(b'D');
    assert_eq!(output.stderr, expected, "{output:?}\n{events}");
    observed_effects(&events, phases, bytes, report);
    eprintln!(
        "native-endian fixture={fixture} instrumented_whole_lifecycle_ms={}",
        elapsed.as_millis()
    );
    output.stdout
}

#[test]
fn native_endian_rejected_accesses_exact_fits_float_transport_and_owned_backing_are_effect_free() {
    assert!(run("contracts", 3, 64, false).is_empty());
}

#[test]
fn native_endian_scale_runs_32768_records_with_one_owner_and_no_phase_host_calls() {
    let bytes = run("scale", 1, 1_179_650, true);
    assert_eq!(bytes.len(), 12);
    let counts: Vec<i32> = bytes
        .chunks_exact(4)
        .map(|word| i32::from_le_bytes(word.try_into().unwrap()))
        .collect();
    assert_eq!(counts, [32768, 196608, 196608]);
    eprintln!(
        "native-endian records=32768 writes=196608 reads=196608 selected_bytes=1114112 backing_bytes=1179650"
    );
}
