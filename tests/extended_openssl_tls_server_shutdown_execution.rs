//! Establish native server-role closure ordering before HTTPS driver policy.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Output},
    sync::OnceLock,
    time::Duration,
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn fixture(name: &str) -> PathBuf {
    root()
        .join("tests/fixtures/extended/openssl_tls_server_shutdown")
        .join(name)
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout(
        "server TLS shutdown experiment",
        command,
        Duration::from_secs(50),
    )
}
fn success(output: &Output) {
    common::assert_command_success("server TLS shutdown experiment", output);
    assert!(output.stderr.is_empty(), "{output:?}");
}
struct Certificates(common::TempArtifact);
impl Certificates {
    fn path(&self) -> &Path {
        self.0.path()
    }
}
impl Drop for Certificates {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(self.path());
    }
}
fn certificates() -> &'static Certificates {
    static DIRECTORY: OnceLock<Certificates> = OnceLock::new();
    DIRECTORY.get_or_init(|| {
        let directory = Certificates(common::TempArtifact::new(
            "laniusc_tls_server_shutdown",
            "certificates",
            None,
        ));
        success(&run(Command::new("python3")
            .arg(root().join("tests/fixtures/extended/openssl_tls/certificates.py"))
            .arg(directory.path())));
        directory
    })
}
fn protocol() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| {
        let observer =
            common::TempArtifact::new("laniusc_tls_server_shutdown", "observer", Some("o"));
        success(&run(Command::new("cc")
            .args(["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-c"])
            .arg(root().join("tests/fixtures/extended/openssl_tls_duplex/observer.c"))
            .arg("-o")
            .arg(observer.path())));
        let entry = fixture("protocol.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let options = laniusc_compiler::compiler::NativeLinkOptions {
            libraries: vec!["ssl".into(), "crypto".into(), "dl".into()],
            objects: vec![observer.path().to_path_buf()],
            ..Default::default()
        };
        let bytes =
            common::run_gpu_codegen_with_timeout("server TLS shutdown native link", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                        &entry, &roots, &options,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("server TLS shutdown: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let executable = common::TempArtifact::new("laniusc_tls_server_shutdown", "protocol", None);
        fs::write(executable.path(), bytes).unwrap();
        success(&run(Command::new("python3")
            .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
            .arg(executable.path())));
        let dynamic = run(Command::new("readelf").arg("-d").arg(executable.path()));
        success(&dynamic);
        let dependencies = String::from_utf8_lossy(&dynamic.stdout);
        assert!(
            dependencies.contains("libssl.so.3") && dependencies.contains("libcrypto.so.3"),
            "{dynamic:?}"
        );
        fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
        executable
    })
}
fn oracle(group: &str) {
    let output = run(Command::new("python3")
        .arg(fixture("oracle.py"))
        .arg(group)
        .arg(protocol().path())
        .arg(certificates().path()));
    success(&output);
    let text = String::from_utf8(output.stdout).unwrap();
    assert!(
        text.contains("openssl-tls-server-shutdown") && text.contains("cases="),
        "{text}"
    );
    println!("{text}");
}
#[test]
fn server_alert_before_drain_classifies_native_upload_policy_for_both_tls_versions() {
    oracle("alert");
}
#[test]
fn server_drain_before_alert_requires_authenticated_peer_eof_for_both_tls_versions() {
    oracle("drain");
}
#[test]
fn server_missing_peer_alert_preserves_confirmed_response_at_the_deadline() {
    oracle("deadline");
}
#[test]
fn server_abrupt_transport_eof_after_response_is_truncation_for_both_tls_versions() {
    oracle("truncation");
}
