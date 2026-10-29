//! Independent raw-byte host peers for named Unix stream addresses.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/unix_stream_address")
        .join(name)
}

#[test]
fn named_unix_streams_preserve_raw_names_boundaries_lifetime_and_failed_connect_status() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = fixture("named.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout("named Unix stream probe", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("named Unix stream probe: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_unix_stream_address", "named", None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "named Unix stream independent host peers",
        Command::new("python3")
            .arg("-B")
            .arg(fixture("oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(85),
    );
    common::assert_command_success("named Unix stream peers", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(
            "unix-stream-address cases=90 peers=52 boundaries=36 backlog=2 layouts=2 "
        ),
        "{summary}"
    );
    eprint!("{summary}");
}
