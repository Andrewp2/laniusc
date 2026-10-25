//! Real OpenSSL mutual TLS credentials, verified peers and explicit owners.
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
        .join("tests/fixtures/extended/openssl_mutual_tls")
        .join(name)
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout(
        "OpenSSL mutual TLS execution",
        command,
        Duration::from_secs(45),
    )
}
fn success(output: &Output) {
    common::assert_command_success("OpenSSL mutual TLS execution", output);
    assert!(output.stderr.is_empty(), "{output:?}");
}

struct Certificates {
    location: common::TempArtifact,
}
impl Certificates {
    fn path(&self) -> &Path {
        self.location.path()
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
        let directory = Certificates {
            location: common::TempArtifact::new("laniusc_mutual_tls", "certificates", None),
        };
        success(&run(Command::new("python3")
            .arg(fixture("certificates.py"))
            .arg(directory.path())));
        directory
    })
}

fn protocol() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| {
        let observer = common::TempArtifact::new("laniusc_mutual_tls", "observer", Some("o"));
        success(&run(Command::new("cc")
            .args(["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-c"])
            .arg(fixture("observer.c"))
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
            common::run_gpu_codegen_with_timeout("OpenSSL mutual TLS native link", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                        &entry, &roots, &options,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("OpenSSL mutual TLS protocol: {error}"));
        let executable = common::TempArtifact::new("laniusc_mutual_tls", "protocol", None);
        fs::write(executable.path(), bytes).unwrap();
        success(&run(Command::new("python3")
            .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
            .arg(executable.path())));
        let dynamic = run(Command::new("readelf").arg("-d").arg(executable.path()));
        success(&dynamic);
        let dependencies = String::from_utf8_lossy(&dynamic.stdout);
        assert!(dependencies.contains("libssl.so.3") && dependencies.contains("libcrypto.so.3"));
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
        text.contains("openssl-mutual-tls") && text.contains("cases="),
        "{text}"
    );
    println!("{text}");
}

#[test]
fn both_roles_verify_tls12_tls13_dns_ip_chain_and_independent_context_lifetimes() {
    oracle("matrix");
}
#[test]
fn required_peers_reject_missing_untrusted_expired_wrong_eku_and_late_alerts() {
    oracle("verification");
}
#[test]
fn shared_credentials_validate_inputs_load_encrypted_keys_and_never_prompt() {
    oracle("credentials");
}
#[test]
fn native_policy_credential_and_required_peer_faults_preserve_diagnostics_and_owners() {
    oracle("faults");
}
#[test]
fn mutual_tls_stable_retries_cover_both_roles_and_real_backpressure() {
    oracle("retries");
}
#[test]
fn each_reached_credential_trust_identity_and_session_staging_failure_cleans_exactly() {
    oracle("allocations");
}
