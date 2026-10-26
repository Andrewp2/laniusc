//! Verified HTTPS through the canonical HTTP protocol and shared batch engine.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn fixture(name: &str) -> PathBuf {
    root()
        .join("tests/fixtures/extended/https_batch")
        .join(name)
}
fn success(label: &str, command: &mut Command) {
    let output = common::process_output_with_timeout(label, command, Duration::from_secs(30));
    common::assert_command_success(label, &output);
    assert!(output.stderr.is_empty(), "{label}: {output:?}");
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
    static FILE: OnceLock<Certificates> = OnceLock::new();
    FILE.get_or_init(|| {
        let location = Certificates(common::TempArtifact::new(
            "https_batch",
            "certificates",
            None,
        ));
        success(
            "HTTPS batch runtime certificates",
            Command::new("python3")
                .arg(root().join("tests/fixtures/extended/openssl_mutual_tls/certificates.py"))
                .arg(location.path()),
        );
        location
    })
}
fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| {
        let observer = common::TempArtifact::new("https_batch", "observer", Some("o"));
        success(
            "HTTPS batch shared native observer",
            Command::new("cc")
                .args(["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-c"])
                .arg(root().join("tests/fixtures/extended/openssl_tls_duplex/observer.c"))
                .arg("-o")
                .arg(observer.path()),
        );
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
        let bytes = common::run_gpu_codegen_with_timeout("HTTPS shared batch fixture", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("HTTPS shared batch fixture: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let file = common::TempArtifact::new("https_batch", "protocol", None);
        fs::write(file.path(), bytes).unwrap();
        success(
            "HTTPS batch linked ELF",
            Command::new("python3")
                .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
                .arg(file.path()),
        );
        let linked = common::process_output_with_timeout(
            "HTTPS batch native dependencies",
            Command::new("readelf").arg("-d").arg(file.path()),
            Duration::from_secs(10),
        );
        common::assert_command_success("HTTPS batch native dependencies", &linked);
        let dependencies = String::from_utf8(linked.stdout).unwrap();
        assert!(dependencies.contains("libssl.so.3") && dependencies.contains("libcrypto.so.3"));
        fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
        file
    })
}
fn oracle(mode: &str) -> String {
    let mut command = Command::new("python3");
    command
        .arg(fixture("oracle.py"))
        .arg(mode)
        .arg(protocol().path())
        .arg(certificates().path());
    if mode == "resources" {
        command.arg(exchange().path());
    }
    let output = common::process_output_with_timeout(
        format!("HTTPS batch {mode}"),
        &mut command,
        Duration::from_secs(90),
    );
    common::assert_command_success(format!("HTTPS batch {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.contains(&format!("https-batch-{mode} cases=")),
        "{summary}"
    );
    eprintln!("{summary}");
    summary
}

fn exchange() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| {
        let observer = common::TempArtifact::new("https_batch", "direct_observer", Some("o"));
        success(
            "HTTPS direct shared observer",
            Command::new("cc")
                .args(["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-c"])
                .arg(root().join("tests/fixtures/extended/openssl_tls_duplex/observer.c"))
                .arg("-o")
                .arg(observer.path()),
        );
        let entry = fixture("exchange.lani");
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
            common::run_gpu_codegen_with_timeout("HTTPS direct Exchange fixture", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                        &entry, &roots, &options,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("HTTPS direct Exchange fixture: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let file = common::TempArtifact::new("https_batch", "exchange", None);
        fs::write(file.path(), bytes).unwrap();
        success(
            "HTTPS direct linked ELF",
            Command::new("python3")
                .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
                .arg(file.path()),
        );
        fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
        file
    })
}

#[test]
fn verified_https_batches_overlap_tcp_and_handshake_then_preserve_input_order_and_cap() {
    oracle("verified");
}

#[test]
fn canonical_http_framing_and_buffered_tls_plaintext_survive_owner_teardown() {
    oracle("framing");
}

#[test]
fn typed_server_verification_and_mutual_tls_failures_preserve_siblings_and_no_peer_http() {
    oracle("policies");
}

#[test]
fn early_final_tls13_authenticated_half_close_and_tls12_deferral_preserve_framing() {
    oracle("transport");
}

#[test]
fn global_deadline_and_retained_result_caps_cancel_active_and_pending_owners() {
    oracle("limits");
}

#[test]
fn resumable_wants_native_faults_and_every_reached_source_allocation_release_resources() {
    oracle("resources");
}
