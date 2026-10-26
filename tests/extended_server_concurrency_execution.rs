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

fn compile(tls: bool) -> common::TempArtifact {
    let label = if tls { "https_serve" } else { "http_serve" };
    let entry = root().join(format!("sample_programs/library/{label}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(async move {
            if tls {
                let options = laniusc_compiler::compiler::NativeLinkOptions {
                    libraries: vec!["ssl".into(), "crypto".into()],
                    ..Default::default()
                };
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                )
                .await
            } else {
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                )
                .await
            }
        })
    })
    .unwrap_or_else(|error| panic!("concurrent {label}: {error}"));
    assert!(
        common::x86_jumps::is_x86_64_executable(&bytes),
        "{label}: expected a native x86_64 executable ELF"
    );
    let executable = common::TempArtifact::new("laniusc_server_concurrency", label, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    if tls {
        let validation = common::process_output_with_timeout(
            "concurrent HTTPS linked ELF",
            Command::new("python3")
                .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
                .arg(executable.path()),
            Duration::from_secs(15),
        );
        common::assert_command_success("concurrent HTTPS linked ELF", &validation);
        let linked = common::process_output_with_timeout(
            "concurrent HTTPS dependencies",
            Command::new("readelf").arg("-d").arg(executable.path()),
            Duration::from_secs(10),
        );
        common::assert_command_success("concurrent HTTPS dependencies", &linked);
        let dependencies = String::from_utf8(linked.stdout).unwrap();
        assert!(
            dependencies.contains("libssl.so.3") && dependencies.contains("libcrypto.so.3"),
            "{dependencies}"
        );
    }
    executable
}

fn program(tls: bool) -> &'static common::TempArtifact {
    static PLAIN: OnceLock<common::TempArtifact> = OnceLock::new();
    static TLS: OnceLock<common::TempArtifact> = OnceLock::new();
    if tls {
        TLS.get_or_init(|| compile(true))
    } else {
        PLAIN.get_or_init(|| compile(false))
    }
}

fn oracle(mode: &str, tls: bool) {
    let output = common::process_output_with_timeout(
        format!("concurrent service {mode}"),
        Command::new("timeout")
            .args(["--kill-after=2s", "38s", "python3"])
            .arg(root().join("tests/fixtures/extended/server_concurrency/oracle.py"))
            .arg(mode)
            .arg(program(tls).path()),
        Duration::from_secs(45),
    );
    common::assert_command_success(format!("concurrent service {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("server-concurrency-{mode} cases=")),
        "{summary}"
    );
    eprint!("{summary}");
}

#[test]
fn partial_plain_head_allows_healthy_response_and_queued_refill_before_release() {
    oracle("plain-refill", false);
}

#[test]
fn withheld_tls_handshake_allows_verified_sibling_and_queued_refill_before_release() {
    oracle("tls-refill", true);
}

#[test]
fn plain_response_backpressure_preserves_healthy_sibling_progress_and_socket_cap() {
    oracle("plain-reader", false);
}

#[test]
fn tls_response_backpressure_preserves_verified_sibling_progress_and_authenticated_close() {
    oracle("tls-reader", true);
}
