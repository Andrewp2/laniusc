//! Direct public Protocol state and owner contracts without an external transport.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

#[test]
fn direct_protocol_reservations_boundaries_and_manual_owners_execute_without_transport() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixture = "tests/fixtures/extended/http_protocol/contracts.lani";
    let entry = root.join(fixture);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(fixture, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{fixture}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_http_protocol", "contracts", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "direct HTTP Protocol contracts and explicit allocation cleanup",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/http_protocol/oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(30),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with("http-protocol states checked allocations="),
        "{summary}"
    );
    assert!(
        summary.contains("explicit-owner-ledger=balanced no-network"),
        "{summary}"
    );
    eprintln!("{summary}");
}
