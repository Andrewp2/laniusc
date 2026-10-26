//! Execute the real bounded unpack program against independent native archives.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]

mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn executable() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/unpack.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("unpack program", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("unpack program: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let artifact = common::TempArtifact::new("laniusc_unpack", "program", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn gate(group: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "unpack native program oracle",
        Command::new("python3")
            .arg("-B")
            .arg(root.join("tests/fixtures/extended/unpack/oracle.py"))
            .arg(group)
            .arg(executable().path()),
        Duration::from_secs(80),
    );
    common::assert_command_success("unpack native program oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII receipt");
    let prefix = format!("PASS unpack group={group} process-cases=");
    let counts: Vec<usize> = summary
        .lines()
        .filter_map(|line| line.strip_prefix(&prefix))
        .map(|count| count.parse().expect("finite process count"))
        .collect();
    assert_eq!(counts.len(), 1, "missing/duplicate receipt: {summary}");
    assert!(counts[0] > 0, "no native unpack processes");
    print!("{summary}");
}

#[test]
fn unpack_real_tar_zip_trees_raw_paths_and_no_replace_partial_publication() {
    gate("tree");
}

#[test]
fn unpack_exact_arguments_help_and_nonregular_inputs_precede_effects() {
    gate("arguments");
}

#[test]
fn unpack_bounded_input_admission_and_run_limits_preserve_namespace() {
    gate("bounds");
}

#[test]
fn unpack_bounded_reporting_preserves_publication_and_primary_failure() {
    gate("report");
}

#[test]
fn unpack_reached_input_interrupt_error_and_invalid_count_preserve_ownership() {
    gate("input_faults");
}
