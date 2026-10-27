//! Public HTTP URL planning, owned snapshots and bounded source-owner failures.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output},
    time::Duration,
};

fn directory() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/extended/http_url")
}

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = directory().join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("HTTP URL {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("http_url_native", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn successful(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn http_url_public_snapshots_numeric_identities_strides_and_destroy_execute() {
    let executable = executable("contracts.lani");
    let output = common::process_output_with_timeout(
        "HTTP URL public contracts",
        &mut Command::new(executable.path()),
        Duration::from_secs(5),
    );
    successful(&output);
    assert!(output.stdout.is_empty(), "{output:?}");
}

#[test]
fn http_url_components_and_diagnostics_match_fixed_semantic_catalog() {
    let executable = executable("model.lani");
    let output = common::process_output_with_timeout(
        "HTTP URL fixed semantic catalog",
        Command::new("python3")
            .arg("-B")
            .arg(directory().join("model.py"))
            .arg(executable.path()),
        Duration::from_secs(25),
    );
    successful(&output);
    assert_eq!(output.stdout, b"http-url model cases=70 layouts=2\n");
}

#[test]
fn http_url_reached_constructor_oom_and_preflight_release_before_exit() {
    let executable = executable("ownership.lani");
    let output = common::process_output_with_timeout(
        "HTTP URL pre-exit ownership and reached OOM",
        Command::new("python3")
            .arg("-B")
            .arg(directory().join("owners.py"))
            .arg(executable.path()),
        Duration::from_secs(75),
    );
    successful(&output);
    let text = String::from_utf8(output.stdout).unwrap();
    assert!(
        text.lines().last().is_some_and(
            |line| line.starts_with("http-url owners cases=") && line.contains(" reached-oom=")
        ),
        "{text}"
    );
}
