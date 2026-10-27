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
        let entry = root().join("sample_programs/library/fetch.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let options = laniusc_compiler::compiler::NativeLinkOptions {
            libraries: vec!["ssl".into(), "crypto".into()],
            ..Default::default()
        };
        let bytes = common::run_gpu_codegen_with_timeout("URL fetch application", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("URL fetch application: {error}"));
        let executable = common::TempArtifact::new("fetch_url", "native", None);
        std::fs::write(executable.path(), bytes).unwrap();
        let checked = common::process_output_with_timeout(
            "URL fetch linked ELF",
            Command::new("python3")
                .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
                .arg(executable.path()),
            Duration::from_secs(20),
        );
        common::assert_command_success("URL fetch linked ELF", &checked);
        let linked = common::process_output_with_timeout(
            "URL fetch shared libraries",
            Command::new("readelf").arg("-d").arg(executable.path()),
            Duration::from_secs(10),
        );
        common::assert_command_success("URL fetch shared libraries", &linked);
        let dependencies = String::from_utf8(linked.stdout).unwrap();
        assert!(dependencies.contains("libssl.so.3") && dependencies.contains("libcrypto.so.3"));
        std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        executable
    })
}
fn oracle(mode: &str, cases: usize) {
    let output = common::process_output_with_timeout(
        format!("URL fetch {mode}"),
        Command::new("python3")
            .arg(root().join("tests/fixtures/extended/fetch_url/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(70),
    );
    common::assert_command_success(format!("URL fetch {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("fetch-url-{mode} cases={cases} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn url_fetch_plain_binary_body_headers_caps_deadline_and_closed_reader_execute() {
    oracle("plain", 24);
}
#[test]
fn url_fetch_cli_url_request_and_configuration_fail_before_network() {
    oracle("preflight", 33);
}
#[test]
fn url_fetch_verified_dns_ip_san_and_explicit_default_ca_paths_execute() {
    oracle("tls", 4);
}
