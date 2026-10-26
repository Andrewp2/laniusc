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
fn fixture(name: &str) -> PathBuf {
    root()
        .join("tests/fixtures/extended/archive_index")
        .join(name)
}
fn compile(entry: PathBuf, label: &'static str) -> common::TempArtifact {
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        libraries: vec!["sqlite3".into()],
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("{label}: {error}"));
    let executable = common::TempArtifact::new("laniusc_archive_index", label, None);
    std::fs::write(executable.path(), bytes).unwrap();
    let validation = common::process_output_with_timeout(
        label,
        Command::new("python3")
            .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
            .arg(executable.path()),
        Duration::from_secs(20),
    );
    common::assert_command_success(label, &validation);
    let dynamic = common::process_output_with_timeout(
        label,
        Command::new("readelf").arg("-d").arg(executable.path()),
        Duration::from_secs(10),
    );
    common::assert_command_success(label, &dynamic);
    if label != "archive stream contracts" {
        assert!(
            String::from_utf8(dynamic.stdout)
                .unwrap()
                .contains("libsqlite3.so")
        );
    }
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn sample_source() -> String {
    std::fs::read_to_string(root().join("sample_programs/library/archive_index.lani")).unwrap()
}
fn variant(name: &str, label: &'static str) -> common::TempArtifact {
    let source = sample_source();
    assert_eq!(source.matches("fn main() -> i32 {").count(), 1);
    let mut source = source.replace("fn main() -> i32 {", "fn command_main() -> i32 {");
    source.push('\n');
    source.push_str(&std::fs::read_to_string(fixture(name)).unwrap());
    let entry = common::TempArtifact::new("laniusc_archive_index", label, Some("lani"));
    entry.write_str(&source);
    compile(entry.path().to_path_buf(), label)
}
fn cli() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        compile(
            root().join("sample_programs/library/archive_index.lani"),
            "archive CLI",
        )
    })
}
fn contracts() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| variant("contracts.lani", "archive ownership"))
}
fn faults() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| variant("faults.lani", "archive fault states"))
}
fn observer() -> &'static common::TempArtifact {
    static LIB: OnceLock<common::TempArtifact> = OnceLock::new();
    LIB.get_or_init(|| {
        let lib = common::TempArtifact::new("laniusc_archive_index", "observer", Some("so"));
        let built = common::process_output_with_timeout(
            "archive observer",
            Command::new("cc")
                .args([
                    "-std=c11", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
                ])
                .arg(fixture("observer.c"))
                .arg("-ldl")
                .arg("-o")
                .arg(lib.path()),
            Duration::from_secs(20),
        );
        common::assert_command_success("archive observer", &built);
        lib
    })
}
fn oracle(mode: &str) {
    let mut command = Command::new("python3");
    command
        .arg(fixture("oracle.py"))
        .arg(mode)
        .arg(cli().path())
        .arg(observer().path());
    // Only the modes exercising these contracts pay for their distinct entry.
    if mode == "matrix" {
        command.arg(contracts().path());
    }
    if mode == "failures" {
        command.arg(cli().path()).arg(faults().path());
    }
    let output = common::process_output_with_timeout(
        format!("archive-index {mode}"),
        &mut command,
        Duration::from_secs(90),
    );
    common::assert_command_success(format!("archive-index {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary
            .lines()
            .last()
            .unwrap()
            .starts_with(&format!("archive-index-{mode} cases=")),
        "{summary}"
    );
    eprint!("{summary}");
}

#[test]
fn immutable_snapshots_duplicate_raw_names_binary_keys_and_owner_lifetimes() {
    oracle("matrix");
}
#[test]
fn exact_and_exceeded_byte_entry_work_and_io_limits_preserve_committed_snapshots() {
    oracle("limits");
}
#[test]
fn all_entry_crc_preflight_and_malformed_catalogs_are_explicit() {
    oracle("corruption");
}
#[test]
fn native_rollback_commit_uncertainty_busy_and_descriptor_failures() {
    oracle("failures");
}
#[test]
fn every_reached_import_and_read_allocation_failure_balances_owned_mappings() {
    oracle("allocations");
}
#[test]
fn thousand_entry_import_indexed_catalog_queries_get_and_exact_export_are_measured() {
    oracle("workload");
}
#[test]
fn scripted_short_io_interruptions_and_call_budgets_execute_sample_helpers() {
    let executable = variant("stream_contracts.lani", "archive stream contracts");
    let output = common::process_output_with_timeout(
        "archive scripted streams",
        &mut Command::new(executable.path()),
        Duration::from_secs(10),
    );
    common::assert_command_success("archive scripted streams", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
