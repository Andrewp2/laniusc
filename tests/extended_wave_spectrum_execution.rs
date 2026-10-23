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
    let exe = common::TempArtifact::new("laniusc_signal", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[test]
fn real_wave_spectrum_filter_csv_limits_and_fault_models() {
    let exe = executable("sample_programs/library/wave_spectrum.lani");
    let output = common::process_output_with_timeout(
        "wave spectrum consumer oracle",
        Command::new("python3")
            .args([
                "-c",
                include_str!("fixtures/extended/wave_spectrum_oracle.py"),
            ])
            .arg(exe.path()),
        Duration::from_secs(45),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}
