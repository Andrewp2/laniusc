//! Owned nested errors through actual persistent Server storage and disposal.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

#[test]
fn actual_server_retains_owned_factory_driver_application_and_abort_errors() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let path = "tests/fixtures/extended/server_poll_ownership/main.lani";
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
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("server_poll_ownership", "native", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "actual Server nested error ownership",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/server_poll_ownership/oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(30),
    );
    common::assert_command_success("actual Server nested error ownership", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout, b"server-poll-ownership cases=3\n");
}
