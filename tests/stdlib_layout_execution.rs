//! Checked byte-layout arithmetic, invariants, precedence and full-width limits.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

#[test]
fn checked_layout_arithmetic_executes_literal_boundaries_without_host_effects() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/layout/contracts.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("checked storage layouts", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("layout contracts: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_layout", "contracts", None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_layout", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "literal layout arithmetic, forged metadata and error precedence",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=all", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(5),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    common::assert_command_success("checked storage layout native contracts", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}\n{events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.starts_with("execve("))
            .count(),
        1,
        "one process entry: {events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.starts_with("exit(") || line.starts_with("exit_group("))
            .count(),
        1,
        "one process exit: {events}"
    );
    let effects: Vec<_> = events
        .lines()
        .filter(|line| {
            !line.starts_with("execve(")
                && !line.starts_with("exit(")
                && !line.starts_with("exit_group(")
        })
        .collect();
    assert!(
        effects.is_empty(),
        "pure layout math must not allocate or call host services: {events}"
    );
}
