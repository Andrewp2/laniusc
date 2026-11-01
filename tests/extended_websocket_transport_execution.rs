//! Pure borrowed-transport contracts; no native socket/TLS/crypto linkage.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

#[test]
fn scripted_upgrade_and_frame_transport_preserve_bytes_and_state_across_partial_io() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/extended/websocket_transport/contracts.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("WebSocket borrowed transport", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("WebSocket transport contracts: {error}"));
    let executable = common::TempArtifact::new("laniusc_websocket_transport", "contracts", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "WebSocket scripted transport contracts",
        &mut Command::new(executable.path()),
        Duration::from_secs(10),
    );
    common::assert_command_success("WebSocket scripted transport contracts", &output);
    assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{output:?}");
}
