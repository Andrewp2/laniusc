//! UTF-8 field selection through bounded directional Text partition cursors.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;
use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/select_field.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("select field", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry,
                    &roots,
                    &Default::default(),
                ),
            )
        })
        .unwrap_or_else(|error| panic!("select field: {error}"));
        let artifact = common::TempArtifact::new("select_field", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(group: &str) {
    let output = common::process_output_with_timeout(
        format!("select field {group}"),
        Command::new("python3")
            .args(["-I", "-B"])
            .arg(root().join("tests/fixtures/stdlib_execution/select_field/oracle.py"))
            .arg(group)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("select field {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("select-field-{group} cases=")),
        "{summary}"
    );
    assert!(summary.contains(" evidence="), "{summary}");
    eprint!("{summary}");
}
#[test]
fn select_field_matches_literal_unicode_fields_in_both_directions() {
    oracle("model");
}
#[test]
fn select_field_validates_arguments_and_utf8_before_publication() {
    oracle("admission");
}
#[test]
fn select_field_enforces_input_record_and_delimiter_limits() {
    oracle("limits");
}
#[test]
fn select_field_reached_allocation_and_io_failures_release_owners() {
    oracle("resources");
}
