//! Actual Prepared/Socket ownership transfer into the canonical HTTP driver.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, sync::OnceLock, time::Duration};

fn root() -> PathBuf { PathBuf::from(env!("CARGO_MANIFEST_DIR")) }
fn compile(name: &str) -> common::TempArtifact {
    let entry = root().join("tests/fixtures/extended/url_adoption").join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")), user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    }).unwrap_or_else(|error| panic!("URL adoption {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("url_adoption", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn probe() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("probe.lani"))
}
fn group(name: &str) {
    let output = common::process_output_with_timeout("HTTP socket adoption oracle",
        Command::new("python3").arg("-B").arg(root().join("tests/fixtures/extended/url_adoption/oracle.py"))
            .arg(probe().path()).arg(name), Duration::from_secs(35));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let expected = if name == "success" { "url-adoption success cases=1 same-generation=1 pre-exit-zero=1\n" }
        else { "url-adoption failures cases=8 reached-close-eio=1 pre-exit-zero=8\n" };
    assert_eq!(output.stdout, expected.as_bytes(), "{output:?}");
}
#[test]
fn public_adoption_consumes_udp_socket_and_prepared_on_rejection() {
    let executable = compile("public_smoke.lani");
    let output = common::process_output_with_timeout("public adoption smoke", &mut Command::new(executable.path()), Duration::from_secs(5));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{output:?}");
}
#[test]
fn connected_socket_generation_reaches_real_http_wire_without_reconnect() { group("success"); }
#[test]
fn invalid_socket_prepared_deadline_and_cleanup_failures_retire_both_inputs() { group("failures"); }
