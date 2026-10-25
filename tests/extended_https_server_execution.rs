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
fn compile(entry: PathBuf) -> common::TempArtifact {
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        libraries: vec!["ssl".into(), "crypto".into()],
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout("https-serve native link", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("https-serve: {error}"));
    let executable = common::TempArtifact::new("laniusc_https_serve", "executable", None);
    std::fs::write(executable.path(), bytes).unwrap();
    let validation = common::process_output_with_timeout(
        "https-serve linked ELF",
        Command::new("python3")
            .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
            .arg(executable.path()),
        Duration::from_secs(20),
    );
    common::assert_command_success("https-serve linked ELF", &validation);
    let linked = common::process_output_with_timeout(
        "https-serve dependencies",
        Command::new("readelf").arg("-d").arg(executable.path()),
        Duration::from_secs(10),
    );
    common::assert_command_success("https-serve dependencies", &linked);
    let dependencies = String::from_utf8(linked.stdout).unwrap();
    assert!(
        dependencies.contains("libssl.so.3") && dependencies.contains("libcrypto.so.3"),
        "{dependencies}"
    );
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn cli() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile(root().join("sample_programs/library/https_serve.lani")))
}
fn stream() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        compile(root().join("tests/fixtures/extended/https_server/stream_contracts.lani"))
    })
}
fn oracle(mode: &str) {
    let executable = if mode == "stream" { stream() } else { cli() };
    let output = common::process_output_with_timeout(
        format!("https-serve {mode}"),
        Command::new("python3")
            .arg(root().join("tests/fixtures/extended/https_server/oracle.py"))
            .arg(mode)
            .arg(executable.path()),
        Duration::from_secs(70),
    );
    common::assert_command_success(format!("https-serve {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("https-serve-{mode} cases=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn verified_clients_exchange_health_binary_fixed_chunked_and_continue_requests() {
    oracle("matrix");
}
#[test]
fn credential_identity_and_http_failures_are_bounded_and_publish_no_response() {
    oracle("failures");
}
#[test]
fn absolute_deadlines_accept_tls_byte_and_parser_work_limits_are_enforced() {
    oracle("limits");
}
#[test]
fn server_stream_consumes_socket_retains_context_and_preserves_buffered_io() {
    oracle("stream");
}
