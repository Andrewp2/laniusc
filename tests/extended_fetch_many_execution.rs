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
fn compile(entry: PathBuf, label: &str) -> common::TempArtifact {
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{label}: {error}"));
    assert!(
        common::x86_jumps::is_x86_64_executable(&bytes),
        "{label}: compiler did not produce an x86_64 executable ELF"
    );
    let executable = common::TempArtifact::new("laniusc_fetch_many", label, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn cli() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        compile(
            root().join("sample_programs/library/fetch_many.lani"),
            "cli",
        )
    })
}
fn oracle(mode: &str) {
    let output = common::process_output_with_timeout(
        format!("fetch-many {mode}"),
        Command::new("python3")
            .arg(root().join("tests/fixtures/extended/fetch_many/oracle.py"))
            .arg(mode)
            .arg(cli().path()),
        Duration::from_secs(75),
    );
    common::assert_command_success(format!("fetch-many {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("fetch-many-{mode} cases=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn csv_jobs_overlap_causally_and_ordered_zip_bodies_comments_match_independent_oracles() {
    oracle("matrix");
}
#[test]
fn invalid_late_jobs_http_status_protocol_and_transport_failures_publish_no_zip() {
    oracle("failures");
}
#[test]
fn exact_csv_body_wire_archive_concurrency_call_and_work_bounds_are_enforced() {
    oracle("limits");
}
#[test]
fn real_and_scripted_input_output_faults_preserve_confirmed_prefix_and_finite_attempts() {
    oracle("io");
    let source =
        std::fs::read_to_string(root().join("sample_programs/library/fetch_many.lani")).unwrap();
    let (helpers, _) = source
        .rsplit_once("fn main() -> i32 {")
        .expect("production entry follows reusable helpers");
    let fixture =
        std::fs::read_to_string(root().join("tests/fixtures/extended/fetch_many/scripted.lani"))
            .unwrap();
    let entry = common::TempArtifact::new("laniusc_fetch_many", "scripted", Some("lani"));
    entry.write_str(&format!("{helpers}\n{fixture}"));
    let executable = compile(entry.path().to_path_buf(), "scripted");
    let output = common::process_output_with_timeout(
        "fetch-many production stream helpers",
        &mut Command::new(executable.path()),
        Duration::from_secs(8),
    );
    common::assert_command_success("fetch-many production stream helpers", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    eprintln!("fetch-many-scripted cases=1 (38 production read_input/publish scenarios)");
}
#[test]
fn every_reached_allocation_failure_cleans_up_and_bounded_scale_keeps_concurrency_cap() {
    oracle("resources");
}
