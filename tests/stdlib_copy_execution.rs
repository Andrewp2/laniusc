//! Resumable generic copying: executable contracts and independent schedules.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/stdlib_copy").join(name)
}
fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let entry = fixture(name);
    let stdlib = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
}
fn executable(name: &str) -> common::TempArtifact {
    let bytes = compile(name).unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_copy", name, None);
    executable.write_bytes(bytes); // Shared in-function jump validation.
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn execute(name: &str) {
    let executable = executable(name);
    let trace = common::TempArtifact::new("laniusc_copy", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "pure resumable copy contracts",
        Command::new("strace").args(["-qq", "-o"]).arg(trace.path())
            .args(["-e", "trace=all", "-e", "signal=none"]).arg(executable.path()),
        Duration::from_secs(15),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    common::assert_command_success(name, &output);
    assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{output:?}\n{events}");
    let mut launches = 0;
    let mut exits = 0;
    for line in events.lines() {
        if line.starts_with("execve(") && line.ends_with("= 0") { launches += 1; }
        else if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") { exits += 1; }
        else { panic!("copy contracts must have no intervening host effects: {events}"); }
    }
    assert_eq!(launches, 1, "{events}");
    assert_eq!(exits, 1, "{events}");
}
#[test]
fn resumable_copy_generic_read_write_execute_tiny_admission() { execute("admission.lani"); }
#[test]
fn resumable_copy_progress_errors_budgets_and_abort_execute() { execute("contracts.lani"); }
#[test]
fn resumable_copy_metadata_faults_counter_headroom_and_strides_execute() { execute("preflight.lani"); }
#[test]
fn resumable_copy_requires_independent_read_and_write_capabilities() {
    for name in ["negative_read.lani", "negative_write.lani"] {
        let error = compile(name).expect_err("copier construction requires the endpoint capability");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic.primary_label.expect("source-local capability rejection");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        assert!(label.source_line.as_deref().unwrap_or("").contains("rejected_copy_bound"), "{name}: {label:?}");
    }
}
#[test]
fn resumable_copy_matches_independent_fifo_payload_and_provider_schedule_model() {
    let executable = executable("model.lani");
    let output = common::process_output_with_timeout(
        "independent resumable copy reference",
        Command::new("python3").arg("-B").arg(fixture("oracle.py")).arg(executable.path()),
        Duration::from_secs(60),
    );
    common::assert_command_success("independent resumable copy reference", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(summary, "copy-model cases=72 actions=348 layouts=2 corruption-controls=12\n");
    eprint!("{summary}");
}
