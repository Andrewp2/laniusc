//! Bounded JSON normalization through borrowed encoding and resumable generic copying.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, sync::OnceLock, time::Duration};

fn root() -> PathBuf { PathBuf::from(env!("CARGO_MANIFEST_DIR")) }
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/json_normalize.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")), user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("streaming JSON normalizer", move || {
            pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))
        }).unwrap_or_else(|error| panic!("JSON normalizer: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes), "JSON normalizer must produce actual ELF64 x86-64");
        let artifact = common::TempArtifact::new("json_normalize", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(group: &str, count: Option<usize>) {
    let output = common::process_output_with_timeout(format!("JSON normalizer {group}"),
        Command::new("python3").arg("-B").arg(root().join("tests/fixtures/stdlib_execution/json_normalize/oracle.py"))
            .arg(group).arg(executable().path()), Duration::from_secs(85));
    common::assert_command_success(format!("JSON normalizer {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    let prefix = match count {
        Some(n) => format!("json-normalize-{group} cases={n} reached_allocations="),
        None => format!("json-normalize-{group} cases="),
    };
    assert!(summary.starts_with(&prefix), "{summary}"); eprint!("{summary}");
}
#[test]
fn json_normalize_streams_exact_compact_bytes_from_an_independent_model() { oracle("model", Some(25)); }
#[test]
fn json_normalize_rejects_arguments_and_invalid_documents_before_stdout() { oracle("admission", Some(15)); }
#[test]
fn json_normalize_observes_byte_probe_and_preflights_exact_document_output_limits() { oracle("limits", Some(9)); }
#[test]
fn json_normalize_reached_allocation_io_and_total_call_failures_release_owners() { oracle("io", None); }
