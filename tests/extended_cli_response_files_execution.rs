//! Actual response-file provider and Expansion ownership on native Linux.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn directory() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/extended/cli_response")
}

fn compile(name: &'static str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = directory().join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("response-file fixture {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("cli_response_files_native", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    eprintln!("response-file executable {}", executable.path().display());
    executable
}

fn files() -> &'static common::TempArtifact {
    static FILES: OnceLock<common::TempArtifact> = OnceLock::new();
    FILES.get_or_init(|| compile("files_probe.lani"))
}

fn oracle(group: &str, owners: bool) {
    let mut command = Command::new("python3");
    command
        .arg("-B")
        .arg(directory().join("files_oracle.py"))
        .arg(group)
        .arg(files().path());
    let owner_executable = owners.then(|| compile("files_owners.lani"));
    if let Some(executable) = &owner_executable {
        command.arg(executable.path());
    }
    let output = common::process_output_with_timeout(
        "response-file native provider/resource oracle",
        &mut command,
        Duration::from_secs(85),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert!(
        stdout.lines().any(|line| line.starts_with(&format!("response-files group={group} cases="))),
        "{stdout}"
    );
    print!("{stdout}");
}

#[test]
fn native_response_provider_files_and_call_failures_execute() {
    oracle("provider", false);
}

#[test]
fn response_expansion_native_and_owned_error_resources_execute() {
    oracle("resources", true);
}
