//! Fixed-capacity reusable regex storage, independent semantics and ownership.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended/regex_workspace")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_regex_workspace", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}

fn gate(group: &str, executable: &common::TempArtifact) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "regex Workspace native oracle",
        Command::new("python3")
            .arg("-B")
            .arg(root.join("tests/fixtures/extended/regex_workspace/oracle.py"))
            .arg(group)
            .arg(executable.path()),
        Duration::from_secs(85),
    );
    common::assert_command_success("regex Workspace native oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII finite receipt");
    let prefix = format!("PASS regex-workspace {group} ");
    assert_eq!(
        summary
            .lines()
            .filter(|line| line.starts_with(&prefix))
            .count(),
        1,
        "{summary}"
    );
    print!("{summary}");
}

#[test]
fn workspace_reuse_and_span_searches_match_independent_models() {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    gate(
        "semantics",
        EXECUTABLE.get_or_init(|| executable("protocol.lani")),
    );
}

#[test]
fn workspace_capacity_reset_cursor_lifetimes_and_zero_allocation_reuse_execute() {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    gate(
        "contracts",
        EXECUTABLE.get_or_init(|| executable("contracts.lani")),
    );
}

#[test]
fn all_nine_workspace_constructor_ooms_release_partial_owners_before_exit() {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    gate(
        "allocations",
        EXECUTABLE.get_or_init(|| executable("allocation.lani")),
    );
}
