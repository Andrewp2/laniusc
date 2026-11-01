//! Checked Base64 profiles over borrowed caller-backed byte Views.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/checked_base64")
        .join(name);
    let stdlib = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
}

fn execute(name: &str) {
    let bytes = compile(name).unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_checked_base64", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_checked_base64", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "checked Base64 native contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=all", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(10),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    common::assert_command_success(name, &output);
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
        "{events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.starts_with("exit(") || line.starts_with("exit_group("))
            .count(),
        1,
        "{events}"
    );
    assert!(
        events.lines().all(|line| line.starts_with("execve(")
            || line.starts_with("exit(")
            || line.starts_with("exit_group(")),
        "pure Base64 codecs must not allocate or call host services: {events}"
    );
}

#[test]
fn checked_base64_profiles_execute_rfc_url_tail_alias_and_error_admission() {
    execute("admission.lani");
}

#[test]
fn checked_base64_profiles_execute_rfc_precedence_lengths_and_atomic_backing_contracts() {
    execute("contracts.lani");
}
