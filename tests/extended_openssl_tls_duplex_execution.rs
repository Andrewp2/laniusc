//! Direct native OpenSSL duplex contracts, with independent bounded TLS peers.
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
        .join("tests/fixtures/extended/openssl_tls_duplex")
        .join(name)
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("OpenSSL TLS duplex", command, Duration::from_secs(50))
}
fn success(output: &Output) {
    common::assert_command_success("OpenSSL TLS duplex", output);
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
            "laniusc_tls_duplex",
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
        let observer = common::TempArtifact::new("laniusc_tls_duplex", "observer", Some("o"));
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
            common::run_gpu_codegen_with_timeout("OpenSSL TLS duplex native link", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                        &entry, &roots, &options,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("OpenSSL TLS duplex: {error}"));
        let executable = common::TempArtifact::new("laniusc_tls_duplex", "protocol", None);
        // Linked code permits PLT targets: use the focused linked-ELF validator.
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
        text.contains("openssl-tls-duplex") && text.contains("cases="),
        "{text}"
    );
    println!("{text}");
}
#[test]
fn real_pending_read_can_write_before_peer_response_and_retains_context_lifetime() {
    oracle("causal");
}
#[test]
fn tls13_local_notification_preserves_trailing_application_data_and_clean_eof() {
    oracle("notification");
}
#[test]
fn injected_rare_wants_preserve_directional_reservations_and_native_retry_buffers() {
    oracle("rare-wants");
}

// Separate fixtures keep the initial three groups immutable while additional
// state-space gates are admitted. This observer is shared read-only with the
// HTTPS batch tests; no control or accounting hook is replaced here.
fn additional_protocol(entry_name: &str, label: &str) -> common::TempArtifact {
    let observer = common::TempArtifact::new("laniusc_tls_duplex", label, Some("o"));
    success(&run(Command::new("cc")
        .args(["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-c"])
        .arg(fixture("observer.c"))
        .arg("-o")
        .arg(observer.path())));
    let entry = fixture(entry_name);
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
        common::run_gpu_codegen_with_timeout("additional TLS duplex native link", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("additional OpenSSL TLS duplex: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_tls_duplex", label, None);
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
}
fn edges_protocol() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| additional_protocol("edges.lani", "edges"))
}
fn edge_oracle(group: &str) {
    let output = run(Command::new("python3")
        .arg(fixture("edge_oracle.py"))
        .arg(group)
        .arg(edges_protocol().path())
        .arg(certificates().path()));
    success(&output);
    let text = String::from_utf8(output.stdout).unwrap();
    assert!(
        text.contains("openssl-tls-duplex edges-") && text.contains("cases="),
        "{text}"
    );
    println!("{text}");
}
#[test]
fn real_write_backpressure_exclusively_retries_owned_bytes_and_native_arguments() {
    edge_oracle("backpressure");
}
#[test]
fn one_native_record_drains_buffered_plaintext_without_fd_readiness() {
    edge_oracle("buffered");
}
#[test]
fn two_ssl_owners_preserve_distinct_staged_writes_across_reverse_retries() {
    edge_oracle("owners");
}
#[test]
fn native_read_write_shutdown_failures_and_real_truncation_release_owners() {
    edge_oracle("failures");
}
#[test]
fn full_shutdown_retries_real_and_injected_wants_until_bidirectional_completion() {
    edge_oracle("shutdown");
}
#[test]
fn every_reached_tls_source_staging_allocation_failure_releases_native_and_source_owners() {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    let executable =
        EXECUTABLE.get_or_init(|| additional_protocol("allocations.lani", "allocations"));
    let output = run(Command::new("python3")
        .arg(fixture("allocation_oracle.py"))
        .arg(executable.path())
        .arg(certificates().path()));
    success(&output);
    let text = String::from_utf8(output.stdout).unwrap();
    assert!(
        text.contains("openssl-tls-duplex allocations cases=6")
            && text.contains("reached-source-oom=5")
            && text.contains("ledger-controls=9"),
        "{text}"
    );
    println!("{text}");
}
