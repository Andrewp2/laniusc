//! Borrowed bidirectional Text: direct execution and capability boundaries.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};
fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    compile_from("tests/fixtures/stdlib_text_bidirectional/direct", name)
}
fn compile_from(
    directory: &str,
    name: &str,
) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(directory).join(name);
    let stdlib = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
}
fn execute(name: &str) {
    let bytes = compile(name).unwrap_or_else(|error| panic!("{name}: {error}"));
    execute_bytes(name, bytes);
}
fn execute_bytes(name: &str, bytes: Vec<u8>) {
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_text_bidirectional", name, None);
    executable.write_bytes(bytes); // Applies shared in-function jump validation.
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_text_bidirectional", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "pure bidirectional Text contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=all", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(15),
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
            panic!("borrowed text traversal must have no intervening host effects: {events}");
        }
    }
    assert_eq!(launches, 1, "{events}");
    assert_eq!(exits, 1, "{events}");
}
#[test]
fn bidirectional_text_all_three_cursors_execute_tiny_admission() {
    execute("admission.lani");
}
#[test]
fn bidirectional_text_exact_partitions_indices_mixed_ends_and_strides_execute() {
    execute("contracts.lani");
}
#[test]
fn bidirectional_text_shared_reverse_take_and_bounded_composition_execute() {
    execute("composition.lani");
}
#[test]
fn bidirectional_text_does_not_claim_metadata_only_exact_size() {
    for name in [
        "negative_exact_lines.lani",
        "negative_exact_scalars.lani",
        "negative_exact_words.lani",
    ] {
        let error =
            compile(name).expect_err("text segmentation cannot supply metadata-only exact counts");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic
            .primary_label
            .expect("source-local capability requirement");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        assert!(
            label
                .source_line
                .as_deref()
                .unwrap_or("")
                .contains("rejected_exact_text_bound"),
            "{name}: {label:?}"
        );
    }
}

// Positive-expected dependency probe: a compiler repair should make this pass.
// Keep it opt-in instead of turning the current compiler failure into success.
#[test]
#[ignore = "generic chained Option method resolution; run explicitly when isolating or fixing"]
fn generic_chained_option_executes_like_explicit_match_on_bounded_slice_cursor() {
    for name in ["typed_match.lani", "chained.lani"] {
        let bytes = compile_from(
            "tests/fixtures/stdlib_compiler_state/text_option_chain",
            name,
        )
        .unwrap_or_else(|error| panic!("{name}: {error}"));
        execute_bytes(name, bytes);
        eprintln!("generic Option dependency native control completed: {name}");
    }
}
