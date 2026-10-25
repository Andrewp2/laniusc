//! Actual Lanius staging mmap failures, distinct from SQLite's own OOM paths.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn fixture(name: &str) -> PathBuf {
    root()
        .join("tests/fixtures/extended/sqlite_allocation")
        .join(name)
}

#[test]
fn each_reached_staging_allocation_failure_preserves_bindings_retries_and_releases_owners() {
    let entry = fixture("staging.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("SQLite staging allocation", move || {
        let options = laniusc_compiler::compiler::NativeLinkOptions {
            libraries: vec!["sqlite3".into()],
            ..Default::default()
        };
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("SQLite staging allocation: {error}"));
    let executable = common::TempArtifact::new("laniusc_sqlite_allocation", "staging", None);
    // This ELF contains platform startup and PLT code; use the linked checker.
    std::fs::write(executable.path(), bytes).unwrap();
    let validation = common::process_output_with_timeout(
        "SQLite staging linked ELF validation",
        Command::new("python3")
            .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
            .arg(executable.path()),
        Duration::from_secs(20),
    );
    common::assert_command_success("SQLite staging linked ELF validation", &validation);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();

    let observer = common::TempArtifact::new("laniusc_sqlite_allocation", "lifecycle", Some("so"));
    let compiled = common::process_output_with_timeout(
        "SQLite staging lifecycle observer",
        Command::new("cc")
            .args([
                "-std=c11", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
            ])
            .arg(fixture("lifecycle.c"))
            .arg("-ldl")
            .arg("-o")
            .arg(observer.path()),
        Duration::from_secs(20),
    );
    common::assert_command_success("SQLite staging lifecycle observer", &compiled);
    let checked = common::process_output_with_timeout(
        "SQLite reached staging mmap failures",
        Command::new("python3")
            .arg(fixture("oracle.py"))
            .arg(executable.path())
            .arg(observer.path()),
        Duration::from_secs(50),
    );
    common::assert_command_success("SQLite reached staging mmap failures", &checked);
    assert!(checked.stderr.is_empty(), "{checked:?}");
    assert_eq!(
        String::from_utf8(checked.stdout).unwrap(),
        "sqlite-allocation cases=5 reached_oom=4 staging_sizes=97,209,313,521 lifecycle=OPTBFC\n"
    );
}
