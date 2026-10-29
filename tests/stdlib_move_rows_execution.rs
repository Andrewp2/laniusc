//! Whole-owner vector transfers in a real staged CSV row mover.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, sync::OnceLock, time::Duration};

fn root() -> PathBuf { PathBuf::from(env!("CARGO_MANIFEST_DIR")) }
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/move_rows.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")), user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("CSV row mover", move || {
            pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))
        }).unwrap_or_else(|error| panic!("CSV row mover: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes), "row mover must produce actual ELF64 x86-64");
        let artifact = common::TempArtifact::new("move_rows", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(group: &str, count: Option<usize>) {
    let output = common::process_output_with_timeout(format!("CSV row mover {group}"),
        Command::new("python3").arg("-B").arg(root().join("tests/fixtures/stdlib_move_rows/oracle.py"))
            .arg(group).arg(executable().path()), Duration::from_secs(85));
    common::assert_command_success(format!("CSV row mover {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    let prefix = match count {
        Some(n) => format!("move-rows-{group} cases={n} reached_allocations="),
        None => format!("move-rows-{group} cases="),
    };
    assert!(summary.starts_with(&prefix), "{summary}"); eprint!("{summary}");
}
#[test]
fn move_rows_matches_independent_canonical_csv_relocation() { oracle("model", Some(33)); }
#[test]
fn move_rows_arguments_csv_and_original_boundaries_are_admitted_before_output() { oracle("admission", Some(29)); }
#[test]
fn move_rows_actual_input_probe_and_csv_boundaries_execute() { oracle("limits", Some(11)); }
#[test]
fn move_rows_reached_allocation_io_and_attempt_failures_retire_nested_owners() { oracle("io", None); }
