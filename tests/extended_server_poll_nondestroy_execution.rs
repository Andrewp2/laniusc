//! Concrete helpers may transfer reports without disposing application errors.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

#[test]
fn both_server_helpers_transfer_empty_reports_without_an_application_destroy_impl() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let path = "tests/fixtures/stdlib_compiler_state/server_poll_nondestroy_admission/main.lani";
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        libraries: vec!["ssl".into(), "crypto".into()],
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let executable = common::TempArtifact::new("server_poll_nondestroy", "native", None);
    executable.write_bytes(bytes);
    let validation = common::process_output_with_timeout(
        "no-Destroy server helpers linked ELF",
        Command::new("python3")
            .arg(root.join("tests/fixtures/native_c/validate_linked_elf.py"))
            .arg(executable.path()),
        // The validator walks every function of a ~10 MB executable (~13 s).
        Duration::from_secs(60),
    );
    common::assert_command_success("no-Destroy server helpers linked ELF", &validation);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();

    let certificate =
        common::TempArtifact::new("server_poll_nondestroy", "certificate", Some("pem"));
    let key = common::TempArtifact::new("server_poll_nondestroy", "key", Some("pem"));
    let credentials = common::process_output_with_timeout(
        "no-Destroy server helpers credentials",
        Command::new("openssl")
            .args([
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-days",
                "1",
                "-subj",
                "/CN=localhost",
            ])
            .arg("-keyout")
            .arg(key.path())
            .arg("-out")
            .arg(certificate.path()),
        Duration::from_secs(15),
    );
    common::assert_command_success("no-Destroy server helpers credentials", &credentials);
    let output = common::process_output_with_timeout(
        "both server helpers without A:Destroy",
        Command::new(executable.path())
            .arg(certificate.path())
            .arg(key.path()),
        Duration::from_secs(10),
    );
    common::assert_command_success("both server helpers without A:Destroy", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
