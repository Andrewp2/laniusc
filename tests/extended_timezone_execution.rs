#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};
fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_timezone", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[test]
fn independent_tzif_zoneinfo_and_annual_transition_models() {
    let exe = executable("tests/fixtures/extended/timezone_model.lani");
    let result = common::process_output_with_timeout(
        "timezone independent models",
        Command::new("python3")
            .args(["-c", include_str!("fixtures/extended/timezone_oracle.py")])
            .arg(exe.path()),
        Duration::from_secs(45),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
}
#[test]
fn owned_bytes_borrowed_designations_and_manual_cleanup() {
    let exe = executable("tests/fixtures/extended/timezone_contracts.lani");
    let result = common::process_output_with_timeout(
        "timezone ownership contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
    assert!(
        result.stdout.is_empty() && result.stderr.is_empty(),
        "{result:?}"
    );
}
