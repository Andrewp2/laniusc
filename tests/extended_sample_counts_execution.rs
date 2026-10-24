#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};
#[test]
fn real_count_csv_prediction_statistics_limits_and_fault_cleanup() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/sample_counts.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("sample-counts", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap();
    let exe = common::TempArtifact::new("laniusc_sample_counts", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "count CSV prediction consumer",
        Command::new("python3")
            .args(["-c", include_str!("fixtures/extended/counts_cli_oracle.py")])
            .arg(exe.path()),
        Duration::from_secs(40),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    println!("{}", String::from_utf8_lossy(&output.stdout));
}
