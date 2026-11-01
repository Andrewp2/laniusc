//! Generic borrowed slice segmentation: direct contracts and capability boundaries.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};
fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    compile_from("tests/fixtures/stdlib_slice_segmentation/direct", name)
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
    let executable = common::TempArtifact::new("laniusc_slice_segmentation", name, None);
    executable.write_bytes(bytes); // Applies shared in-function jump validation.
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_slice_segmentation", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "pure slice segmentation contracts",
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
            panic!("borrowed slice segmentation must have no intervening host effects: {events}");
        }
    }
    assert_eq!(launches, 1, "{events}");
    assert_eq!(exits, 1, "{events}");
}
#[test]
fn slice_segmentation_all_three_generic_cursors_execute_tiny_admission() {
    execute("admission.lani");
}
#[test]
fn slice_segmentation_partitions_callback_effects_bounds_and_strides_execute() {
    execute("contracts.lani");
}
#[test]
fn slice_segmentation_compound_values_alias_edits_and_borrowed_composition_execute() {
    execute("composition.lani");
}
fn reject(names: &[&str]) {
    for &name in names {
        let error = compile(name).expect_err("traversal must require the declared capability");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic
            .primary_label
            .expect("source-local capability rejection");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        assert!(
            label
                .source_line
                .as_deref()
                .unwrap_or("")
                .contains("rejected_segmentation_bound"),
            "{name}: {label:?}"
        );
    }
}
#[test]
fn slice_segmentation_enforces_mapper_item_and_output_capabilities() {
    reject(&[
        "negative_split_missing_mapper.lani",
        "negative_inclusive_wrong_item.lani",
        "negative_chunk_wrong_pair.lani",
        "negative_split_wrong_output.lani",
        "negative_inclusive_missing_mapper.lani",
        "negative_chunk_wrong_output.lani",
    ]);
}
#[test]
fn slice_segmentation_does_not_claim_reverse_or_exact_size() {
    reject(&[
        "negative_split_reverse.lani",
        "negative_inclusive_reverse.lani",
        "negative_chunk_reverse.lani",
        "negative_split_exact.lani",
        "negative_inclusive_exact.lani",
        "negative_chunk_exact.lani",
    ]);
}
