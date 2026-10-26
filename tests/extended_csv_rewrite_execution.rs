#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
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
fn compile(entry: PathBuf) -> common::TempArtifact {
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("csv-rewrite", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("csv-rewrite: {error}"));
    let executable = common::TempArtifact::new("laniusc_csv_rewrite", "executable", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn cli() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile(root().join("sample_programs/library/csv_rewrite.lani")))
}
fn scripted() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let source =
            std::fs::read_to_string(root().join("sample_programs/library/csv_rewrite.lani"))
                .unwrap();
        let (helpers, _) = source
            .rsplit_once("fn main() -> i32 {")
            .expect("production entry follows reusable helpers");
        let fixtures = std::fs::read_to_string(
            root().join("tests/fixtures/extended/csv_rewrite/scripted.lani"),
        )
        .unwrap();
        let entry = common::TempArtifact::new("laniusc_csv_rewrite", "scripted", Some("lani"));
        entry.write_str(&format!("{helpers}\n{fixtures}"));
        compile(entry.path().to_path_buf())
    })
}
fn oracle(mode: &str) {
    let output = common::process_output_with_timeout(
        format!("csv-rewrite {mode}"),
        Command::new("python3")
            .arg(root().join("tests/fixtures/extended/csv_rewrite/oracle.py"))
            .arg(mode)
            .arg(cli().path()),
        Duration::from_secs(70),
    );
    common::assert_command_success(format!("csv-rewrite {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("csv-rewrite-{mode} cases=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn selected_reordered_duplicate_utf8_columns_match_independent_python_csv() {
    oracle("matrix");
}
#[test]
fn input_output_record_field_work_and_call_bounds_preserve_confirmed_prefix() {
    oracle("limits");
}
#[test]
fn real_short_output_broken_pipes_interruption_and_host_errors_are_bounded() {
    oracle("io");
}
#[test]
fn every_allocation_failure_cleans_up_and_thousands_of_rows_reuse_bounded_storage() {
    oracle("resources");
}
#[test]
fn actual_transform_helpers_handle_scripted_short_reads_writes_and_flush_failures() {
    let output = common::process_output_with_timeout(
        "csv-rewrite scripted",
        &mut Command::new(scripted().path()),
        Duration::from_secs(8),
    );
    common::assert_command_success("csv-rewrite scripted", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    eprintln!("csv-rewrite-scripted cases=1 (all chunk schedules and bounded IO scenarios)");
}
