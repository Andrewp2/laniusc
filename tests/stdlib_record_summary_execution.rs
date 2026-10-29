//! Full binary TSV record summaries and bounded whole-input/publication failure behavior.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, sync::OnceLock, time::Duration};

fn root() -> PathBuf { PathBuf::from(env!("CARGO_MANIFEST_DIR")) }
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/record_summary.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")), user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("record summary application", move || {
            pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))
        }).unwrap_or_else(|error| panic!("record summary: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes), "record summary must produce actual ELF64 x86-64");
        let artifact = common::TempArtifact::new("record_summary", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(group: &str, count: Option<usize>) {
    let output = common::process_output_with_timeout(format!("record summary {group}"),
        Command::new("python3").arg("-B").arg(root().join("tests/fixtures/stdlib_execution/record_summary/oracle.py"))
            .arg(group).arg(executable().path()), Duration::from_secs(85));
    common::assert_command_success(format!("record summary {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    let prefix = match count {
        Some(n) => format!("record-summary-{group} cases={n} reached_allocations="),
        None => format!("record-summary-{group} cases="),
    };
    assert!(summary.starts_with(&prefix), "{summary}"); eprint!("{summary}");
}
#[test]
fn record_summary_matches_independent_complete_tsv_for_binary_record_partitions() { oracle("model", Some(48)); }
#[test]
fn record_summary_rejects_arguments_without_allocating_or_reading() { oracle("admission", Some(8)); }
#[test]
fn record_summary_exact_byte_probe_and_record_limits_execute() { oracle("limits", Some(8)); }
#[test]
fn record_summary_reached_allocation_io_and_attempt_failures_release_owners() { oracle("io", None); }
