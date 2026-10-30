//! Lazy outcomes: exact branches, callback effects, generic values, and trait bounds.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/stdlib_lazy_outcomes").join(name)
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
    let executable = common::TempArtifact::new("laniusc_lazy_outcomes", name, None);
    executable.write_bytes(bytes); // Shared in-function jump validation.
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn execute(name: &str) {
    let executable = executable(name);
    let trace = common::TempArtifact::new("laniusc_lazy_outcomes", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "lazy outcome direct contracts",
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
        else { panic!("unexpected lazy outcome host effect: {events}"); }
    }
    assert_eq!((launches,exits), (1,1), "{events}");
}
#[test]
fn lazy_outcomes_canonical_callbacks_execute_tiny_admission() { execute("admission.lani"); }
#[test]
fn lazy_outcomes_all_free_and_method_branches_execute_without_host_effects() { execute("branches.lani"); }
#[test]
fn lazy_outcomes_generic_compound_float_view_and_zero_size_values_execute() { execute("types.lani"); }
fn reject_bounds(names: &[&str]) {
    for name in names {
        let error = compile(name).expect_err("lazy outcomes require exact callback capabilities even on skipped branches");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic.primary_label.expect("source-local capability rejection");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        assert!(label.source_line.as_deref().unwrap_or("").contains("rejected_outcome_bound"), "{name}: {label:?}");
    }
}
#[test]
fn lazy_option_requires_exact_mapper_and_producer_bounds_on_skipped_branches() {
    reject_bounds(&["negative_option_missing_mapper.lani", "negative_option_mapper_input.lani",
        "negative_option_mapper_output.lani", "negative_option_missing_producer.lani",
        "negative_option_producer_output.lani", "negative_option_filter_bool.lani",
        "negative_option_unselected_fallback.lani", "negative_option_unselected_mapper.lani"]);
}
#[test]
fn lazy_result_requires_matching_values_errors_and_both_callback_bounds() {
    reject_bounds(&["negative_result_chain_error.lani", "negative_result_recovery_value.lani",
        "negative_result_error_input.lani", "negative_result_predicate_bool.lani",
        "negative_result_unselected_fallback.lani", "negative_result_unselected_mapper.lani"]);
}
