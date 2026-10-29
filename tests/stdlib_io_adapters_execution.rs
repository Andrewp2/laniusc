//! Borrowed Take/Chain: exact quotas, shared protocol state and provider faults.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_io_adapters").join(name);
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
    let executable = common::TempArtifact::new("laniusc_io_adapters", name, None);
    executable.write_bytes(bytes); // Shared checks reject jumps outside their functions.
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_io_adapters", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "borrowed reader adapter native contracts",
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
    let mut launches = 0;
    let mut exits = 0;
    for line in events.lines() {
        if line.starts_with("execve(") && line.ends_with("= 0") {
            launches += 1;
        } else if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            exits += 1;
        } else {
            panic!("pure byte-reader adapters must have no host effects: {events}");
        }
    }
    assert_eq!(launches, 1, "{events}");
    assert_eq!(exits, 1, "{events}");
}
#[test]
fn borrowed_reader_adapters_execute_mixed_protocol_and_nested_admission() {
    execute("admission.lani");
}
#[test]
fn borrowed_reader_adapters_preserve_quotas_handoff_errors_faults_and_actual_strides() {
    execute("contracts.lani");
}
#[test]
fn borrowed_reader_adapters_preflight_full_ranges_zero_requests_and_capability_independence() {
    execute("preflight.lani");
}
#[test]
fn borrowed_reader_adapter_read_and_bufread_bounds_are_independent() {
    for name in [
        "negative_take_read.lani",
        "negative_take_bufread.lani",
        "negative_chain_read.lani",
        "negative_chain_bufread.lani",
        "negative_chain_first_read.lani",
        "negative_chain_first_bufread.lani",
    ] {
        let error = compile(name)
            .expect_err("the requested protocol must exist on every selected provider type");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic
            .primary_label
            .expect("missing adapter protocol bound");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        let line = label.source_line.as_deref().unwrap_or("");
        assert!(
            line.contains("require_") && line.contains("rejected_adapter_bound"),
            "relevant adapter capability: {label:?}"
        );
    }
}
