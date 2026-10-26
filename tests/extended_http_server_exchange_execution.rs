//! Direct resumable server calls against independent HTTP peers and syscall epochs.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let path = "tests/fixtures/extended/http_server_exchange/probe.lani";
        let entry = root().join(path);
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout(path, move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("{path}: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let executable = common::TempArtifact::new("http_server_exchange", "native", None);
        executable.write_bytes(bytes);
        std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700))
            .unwrap();
        executable
    })
}

fn group(name: &str) {
    let output = common::process_output_with_timeout(
        format!("HTTP server Exchange {name}"),
        Command::new("python3")
            .arg(root().join("tests/fixtures/extended/http_server_exchange/oracle.py"))
            .arg(executable().path())
            .arg(name),
        Duration::from_secs(80),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("http-server-exchange-{name} cases=")),
        "{summary}"
    );
    eprintln!("{summary}");
}

#[test]
fn server_steps_have_one_active_socket_leaf_and_external_waits() {
    group("steps");
}

#[test]
fn server_protocol_decisions_expect_and_stable_views_survive_backing_growth() {
    group("decisions");
}

#[test]
fn server_early_rejection_duplex_backpressure_and_exact_eof_probe_execute() {
    group("drain");
}

#[test]
fn server_terminal_replay_abort_and_destruction_release_each_owner_once() {
    group("lifecycle");
}

#[test]
fn server_direct_errors_keep_progress_and_reached_allocation_failures_release_owners() {
    group("faults");
}
