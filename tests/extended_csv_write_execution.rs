#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn fixture(name: &str) -> PathBuf {
    root().join("tests/fixtures/extended/csv_write").join(name)
}
fn executable(name: &str) -> common::TempArtifact {
    let entry = fixture(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("CSV writer {name}: {error}"));
    let executable = common::TempArtifact::new("laniusc_csv_write", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn native(name: &str) {
    let executable = executable(name);
    let result = common::process_output_with_timeout(
        name,
        &mut Command::new(executable.path()),
        Duration::from_secs(10),
    );
    common::assert_command_success(name, &result);
    assert!(
        result.stdout.is_empty() && result.stderr.is_empty(),
        "{result:?}"
    );
}
fn oracle(mode: &str, entry: &str) {
    let executable = executable(entry);
    let result = common::process_output_with_timeout(
        format!("CSV write {mode}"),
        Command::new("python3")
            .arg(fixture("oracle.py"))
            .arg(mode)
            .arg(executable.path()),
        Duration::from_secs(60),
    );
    common::assert_command_success(mode, &result);
    assert!(result.stderr.is_empty(), "{result:?}");
    let summary = String::from_utf8(result.stdout).unwrap();
    assert!(summary.starts_with("csv-write-"), "{summary}");
    eprint!("{summary}");
}

#[test]
fn canonical_bytes_match_python_csv_for_unicode_quotes_crlf_and_empty_shapes() {
    oracle("matrix", "protocol.lani");
}
#[test]
fn every_short_record_failure_prefix_and_large_chunk_boundary_has_exact_progress() {
    native("contracts.lani");
}
#[test]
fn malformed_record_and_text_metadata_fail_before_any_writer_call() {
    native("metadata.lani");
}
#[test]
fn every_staged_growth_failure_preserves_record_capacities_views_and_self_aliases() {
    oracle("allocations", "allocation.lani");
}
#[test]
fn record_reuse_and_stream_writing_allocate_nothing_after_warmup_and_never_flush() {
    oracle("noalloc", "noalloc.lani");
}
