//! Focused consumer acceptance for owned vector filtering/deduplication/truncation.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, sync::OnceLock, time::Duration};

fn root() -> PathBuf { PathBuf::from(env!("CARGO_MANIFEST_DIR")) }
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/sort_rows.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")), user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("CSV owned-row editing application", move || {
            pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))
        }).unwrap_or_else(|error| panic!("sort rows edit: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let artifact = common::TempArtifact::new("sort_rows_edit", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(group: &str, count: Option<usize>) {
    let output = common::process_output_with_timeout(
        format!("sort rows edit {group}"),
        Command::new("python3").arg("-B").arg(root().join("tests/fixtures/sort_rows_edit/oracle.py"))
            .arg(group).arg(executable().path()), Duration::from_secs(85),
    );
    common::assert_command_success(format!("sort rows edit {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    let prefix = count.map_or_else(|| format!("sort-rows-edit-{group} cases="),
                                  |count| format!("sort-rows-edit-{group} cases={count} "));
    assert!(summary.starts_with(&prefix), "{summary}");
    eprint!("{summary}");
}

#[test]
fn sort_rows_owned_edits_match_independent_csv_pipeline() { oracle("model", Some(22)); }
#[test]
fn sort_rows_edits_validate_complete_input_and_actual_caps() { oracle("admission", Some(17)); }
#[test]
fn sort_rows_edit_options_validate_before_input() { oracle("cli", Some(26)); }
#[test]
fn sort_rows_owned_edits_reached_failures_cleanup_before_publication() { oracle("io", None); }
