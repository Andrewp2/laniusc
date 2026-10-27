#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::Command,
    sync::OnceLock,
    time::Duration,
};
fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn compile(source: &str, label: &str, secure: bool) -> common::TempArtifact {
    let entry = root().join(source);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    // Plain URL imports intentionally have no SSL/crypto link dependency.
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        libraries: if secure {
            vec!["ssl".into(), "crypto".into()]
        } else {
            vec![]
        },
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("{label}: {error}"));
    let executable = common::TempArtifact::new("laniusc_url_client", label, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let checked = common::process_output_with_timeout(
        "URL client linked ELF",
        Command::new("python3")
            .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
            .arg(executable.path()),
        Duration::from_secs(20),
    );
    common::assert_command_success("URL client linked ELF", &checked);
    executable
}
fn plain() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        compile(
            "tests/fixtures/extended/url_client/plain_probe.lani",
            "plain",
            false,
        )
    })
}
fn oracle(mode: &str, executable: &Path) -> String {
    let output = common::process_output_with_timeout(
        format!("URL client {mode}"),
        Command::new("python3")
            .arg(root().join("tests/fixtures/extended/url_client/oracle.py"))
            .arg(mode)
            .arg(executable),
        Duration::from_secs(75),
    );
    common::assert_command_success(format!("URL client {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    eprint!("{summary}");
    summary
}
#[test]
fn numeric_url_preserves_host_target_binary_body_and_selected_socket_without_reconnect() {
    assert!(oracle("plain", plain().path()).contains("url-client-plain cases=2"));
}

fn tls() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        compile(
            "tests/fixtures/extended/url_client/tls_probe.lani",
            "tls",
            true,
        )
    })
}
fn observer() -> &'static common::TempArtifact {
    static SO: OnceLock<common::TempArtifact> = OnceLock::new();
    SO.get_or_init(|| {
        let artifact = common::TempArtifact::new("laniusc_url_client", "observer", Some("so"));
        let output = common::process_output_with_timeout(
            "URL client loopback NSS observer",
            Command::new("cc")
                .args([
                    "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", "-shared", "-fPIC",
                ])
                .arg(root().join("tests/fixtures/extended/url_client/resolver_observer.c"))
                .arg("-o")
                .arg(artifact.path())
                .arg("-ldl"),
            Duration::from_secs(20),
        );
        common::assert_command_success("URL client loopback NSS observer", &output);
        artifact
    })
}
fn connected_oracle(script: &str, executable: &Path) -> String {
    let output = common::process_output_with_timeout(
        format!("URL client {script}"),
        Command::new("python3")
            .arg(
                root()
                    .join("tests/fixtures/extended/url_client")
                    .join(script),
            )
            .arg(executable)
            .arg(observer().path()),
        Duration::from_secs(75),
    );
    common::assert_command_success(format!("URL client {script}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    eprint!("{summary}");
    summary
}
#[test]
fn dns_url_preserves_nss_order_retires_refused_endpoint_and_adopts_one_selected_fd() {
    assert!(connected_oracle("dns_oracle.py", plain().path()).contains("url-client-dns cases=1"));
}
#[test]
fn url_tls_verifies_original_dns_or_ip_and_never_replays_after_tls_or_http_failure() {
    assert!(connected_oracle("tls_oracle.py", tls().path()).contains("url-client-tls cases=8"));
}
