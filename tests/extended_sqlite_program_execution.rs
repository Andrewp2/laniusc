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
fn compile(entry: PathBuf, require_sqlite: bool) -> common::TempArtifact {
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        libraries: vec!["sqlite3".into()],
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout("sqlite-kv native link", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("sqlite-kv: {error}"));
    let executable = common::TempArtifact::new("laniusc_sqlite_program", "executable", None);
    std::fs::write(executable.path(), bytes).unwrap();
    let validation = common::process_output_with_timeout(
        "sqlite-kv linked ELF validation",
        Command::new("python3")
            .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
            .arg(executable.path()),
        Duration::from_secs(20),
    );
    common::assert_command_success("sqlite-kv linked ELF validation", &validation);
    let dynamic = common::process_output_with_timeout(
        "sqlite-kv native dependencies",
        Command::new("readelf").arg("-d").arg(executable.path()),
        Duration::from_secs(10),
    );
    common::assert_command_success("sqlite-kv native dependencies", &dynamic);
    let dependencies = String::from_utf8(dynamic.stdout).unwrap();
    if require_sqlite {
        assert!(dependencies.contains("libsqlite3.so"), "{dependencies}");
    }
    assert!(!dependencies.contains("libcrypto"), "{dependencies}");
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn cli() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile(root().join("sample_programs/library/sqlite_kv.lani"), true))
}
fn observer() -> &'static common::TempArtifact {
    static LIBRARY: OnceLock<common::TempArtifact> = OnceLock::new();
    LIBRARY.get_or_init(|| {
        let library = common::TempArtifact::new("laniusc_sqlite_program", "lifecycle", Some("so"));
        let output = common::process_output_with_timeout(
            "sqlite-kv test lifecycle observer",
            Command::new("cc")
                .args([
                    "-std=c11", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
                ])
                .arg(root().join("tests/fixtures/extended/sqlite_program/lifecycle.c"))
                .arg("-ldl")
                .arg("-o")
                .arg(library.path()),
            Duration::from_secs(20),
        );
        common::assert_command_success("sqlite-kv test lifecycle observer", &output);
        library
    })
}
fn oracle(mode: &str) {
    let output = common::process_output_with_timeout(
        format!("sqlite-kv {mode}"),
        Command::new("python3")
            .arg(root().join("tests/fixtures/extended/sqlite_program/oracle.py"))
            .arg(mode)
            .arg(cli().path())
            .arg(observer().path()),
        Duration::from_secs(50),
    );
    common::assert_command_success(format!("sqlite-kv {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(summary.starts_with(&format!("sqlite-program-{mode} cases=")));
    eprint!("{summary}");
}
#[test]
fn persisted_binary_values_raw_keys_and_upserts_interoperate_with_python_sqlite() {
    oracle("matrix");
}
#[test]
fn arguments_input_output_and_io_attempt_limits_preserve_existing_rows() {
    oracle("limits");
}
#[test]
fn readonly_busy_constraint_missing_and_invalid_database_errors_are_explicit() {
    oracle("errors");
}
#[test]
fn descriptor_failures_preserve_prior_values_and_original_error_status() {
    oracle("io");
}
#[test]
fn short_transfers_interruptions_zero_progress_and_retry_budgets_execute_actual_sample_helpers() {
    let sample =
        std::fs::read_to_string(root().join("sample_programs/library/sqlite_kv.lani")).unwrap();
    assert_eq!(sample.matches("fn main() -> i32 {").count(), 1);
    let mut source = sample.replace("fn main() -> i32 {", "fn command_main() -> i32 {");
    source.push('\n');
    source.push_str(
        &std::fs::read_to_string(
            root().join("tests/fixtures/extended/sqlite_program/stream_contracts.lani"),
        )
        .unwrap(),
    );
    let entry = common::TempArtifact::new("laniusc_sqlite_program", "streams", Some("lani"));
    entry.write_str(&source);
    let executable = compile(entry.path().to_path_buf(), false);
    let output = common::process_output_with_timeout(
        "sqlite-kv scripted streams",
        &mut Command::new(executable.path()),
        Duration::from_secs(10),
    );
    common::assert_command_success("sqlite-kv scripted streams", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
