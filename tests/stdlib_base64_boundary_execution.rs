//! Checked Base64 exact-alias and physical access boundaries.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/checked_base64_boundaries")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("checked Base64 boundaries", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("checked Base64 {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_base64_boundary", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn result(line: &str) -> &str {
    line.rsplit_once('=').unwrap().1.trim()
}
fn address(value: &str) -> usize {
    usize::from_str_radix(value.trim().strip_prefix("0x").unwrap(), 16).unwrap()
}

fn effects(events: &str) {
    let mut mapping: Option<(String, usize)> = None;
    let mut pure = false;
    let mut phases = 0;
    let mut done = false;
    let mut entries = 0;
    let mut exits = 0;
    let mut allocations = 0;
    let mut protections = 0;
    let mut releases = 0;
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert_eq!(result(line), "1", "{events}");
            if line.contains("\"P\", 1)") {
                assert!(
                    !pure && !done && protections == 1,
                    "guard established before codec phase: {events}"
                );
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
                        && mapping.is_none()
                        && releases == 1,
                    "explicit cleanup before D: {events}"
                );
                done = true;
            }
            continue;
        }
        assert!(!pure, "codec phase reached a host service: {line}");
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done, "exit follows completed cleanup: {events}");
            exits += 1;
            continue;
        }
        assert!(!done, "only exit follows D: {events}");
        if line.starts_with("execve(") {
            assert_eq!(result(line), "0", "{events}");
            entries += 1;
        } else if let Some(arguments) = line.strip_prefix("mmap(") {
            assert!(
                mapping.is_none() && allocations == 0 && phases == 0,
                "one backing before all phases: {events}"
            );
            let size: usize = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let pointer = result(line).split_whitespace().next().unwrap();
            assert_eq!(size, 8192, "guarded two-page extent: {events}");
            assert!(
                pointer.starts_with("0x"),
                "actual successful mapping: {events}"
            );
            assert_eq!(
                address(pointer) % 4096,
                0,
                "native guard-page alignment: {events}"
            );
            mapping = Some((pointer.to_owned(), size));
            allocations += 1;
        } else if let Some(arguments) = line.strip_prefix("mprotect(") {
            assert!(
                protections == 0 && phases == 0,
                "one protection before all phases: {events}"
            );
            let arguments = arguments.split_once(')').unwrap().0;
            let fields: Vec<_> = arguments.split(',').map(str::trim).collect();
            assert_eq!(fields.len(), 3, "{events}");
            let (pointer, _) = mapping.as_ref().unwrap();
            assert_eq!(
                address(fields[0]),
                address(pointer).checked_add(4096).unwrap(),
                "second page guard: {events}"
            );
            assert_eq!(fields[1], "4096", "{events}");
            assert_eq!(fields[2], "PROT_NONE", "{events}");
            assert_eq!(result(line), "0", "{events}");
            protections += 1;
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            assert_eq!(phases, 7, "backing stays live through codecs: {events}");
            let arguments = arguments.split_once(')').unwrap().0;
            let (pointer, size) = arguments.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            assert_eq!(
                mapping.take(),
                Some((pointer.trim().to_owned(), size)),
                "exact backing release: {events}"
            );
            assert_eq!(result(line), "0", "{events}");
            releases += 1;
        } else {
            panic!("unexpected host service: {line}");
        }
    }
    assert!(done && !pure && mapping.is_none(), "{events}");
    assert_eq!(
        (entries, exits, allocations, protections, releases, phases),
        (1, 1, 1, 1, 1, 7),
        "{events}"
    );
}

#[test]
fn checked_base64_respects_exact_aliases_strides_guard_pages_and_atomic_failures() {
    let executable = executable("contracts.lani");
    let trace = common::TempArtifact::new("laniusc_base64_boundary", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "checked Base64 honest memory boundaries",
        Command::new("strace")
            .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=all", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(15),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    assert!(output.stdout.is_empty(), "{output:?}");
    let mut markers = b"Pp".repeat(7);
    markers.push(b'D');
    assert_eq!(output.stderr, markers, "{output:?}\n{events}");
    effects(&events);
    eprintln!(
        "checked-base64-boundaries profiles=4 lengths=11 layouts=3 pure-phases=7 guarded-mappings=1 protections=1 releases=1"
    );
}

#[test]
fn checked_base64_logical_overclaims_preserve_the_physical_backing_precondition() {
    for name in ["read_overclaim.lani", "write_overclaim.lani"] {
        let executable = executable(name);
        let output = common::process_output_with_timeout(
            name,
            &mut Command::new(executable.path()),
            Duration::from_secs(5),
        );
        assert_eq!(
            output.status.code(),
            Some(101),
            "actual native backing bounds trap in {name}: {output:?}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{name}: {output:?}"
        );
    }
}
