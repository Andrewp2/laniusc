#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};
#[test]
fn timezone_tool_conversion_resolution_staging_and_fault_cleanup() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/timezone_tool.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("timezone-tool", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap();
    let exe = common::TempArtifact::new("laniusc_timezone_tool", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let result = common::process_output_with_timeout(
        "timezone-tool independent consumer and syscall oracle",
        Command::new("python3")
            .args([
                "-c",
                include_str!("fixtures/extended/timezone_tool_oracle.py"),
            ])
            .arg(exe.path())
            .current_dir(env!("CARGO_MANIFEST_DIR")),
        Duration::from_secs(45),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
}
