//! Connector admission, bounded fallback and explicit owner retirement.
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

fn probe() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("tests/fixtures/extended/url_connect/probe.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        // Resolver calls need native linking; this connector has no TLS
        // dependency and deliberately links without SSL/crypto libraries.
        let options = laniusc_compiler::compiler::NativeLinkOptions::default();
        let bytes = common::run_gpu_codegen_with_timeout("URL connector probe", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("URL connector probe: {error}"));
        let executable = common::TempArtifact::new("laniusc_url_connect", "probe", None);
        executable.write_bytes(bytes);
        std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700))
            .unwrap();
        let checked = common::process_output_with_timeout(
            "URL connector linked ELF",
            Command::new("python3")
                .arg("-B")
                .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
                .arg(executable.path()),
            Duration::from_secs(20),
        );
        common::assert_command_success("URL connector linked ELF", &checked);
        executable
    })
}

fn observer() -> &'static common::TempArtifact {
    static SO: OnceLock<common::TempArtifact> = OnceLock::new();
    SO.get_or_init(|| {
        let artifact = common::TempArtifact::new("laniusc_url_connect", "observer", Some("so"));
        let output = common::process_output_with_timeout(
            "URL connector test NSS observer",
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
        common::assert_command_success("URL connector test NSS observer", &output);
        artifact
    })
}

fn group(name: &str, expected_cases: usize) {
    let output = common::process_output_with_timeout(
        format!("URL connector {name}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/extended/url_connect/oracle.py"))
            .arg(name)
            .arg(probe().path())
            .arg(observer().path()),
        Duration::from_secs(75),
    );
    common::assert_command_success(format!("URL connector {name}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    eprint!("{summary}");
    assert!(summary.contains(&format!(
        "url-connect group={name} cases={expected_cases} evidence="
    )));
}

#[test]
fn connector_rejects_invalid_limits_deadlines_and_family_before_attempting_an_endpoint() {
    group("admission", 12);
}

#[test]
fn connector_bounds_ordered_fallback_preserves_resolver_errors_and_retires_failed_sockets() {
    group("failures", 8);
}
