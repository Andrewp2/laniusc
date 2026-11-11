#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;

use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};

fn build(label: &str, path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{label}: {error}"));
    let exe = common::TempArtifact::new("laniusc_patchset", label, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn available(tool: &str) -> bool {
    Command::new(tool).arg("--version").output().map(|o| o.status.success()).unwrap_or(false)
}

#[test]
fn patchset_api_contracts() {
    let exe = build("contracts", "tests/fixtures/extended/patchset_contracts.lani");
    let output = common::process_output_with_timeout(
        "patchset contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(30),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}

// Patches from git diff (renames, copies, modes, creation, deletion, binary
// files) applied to mutated trees: the resulting tree and exit status must
// match GNU patch (-t, -N, -f, -R), git apply (and -R) and git apply --3way.
#[test]
fn seq_patch_matches_gnu_patch_and_git_apply() {
    if !available("git") || !available("patch") || !available("python3") {
        eprintln!("skipping: git, GNU patch and python3 are required");
        return;
    }
    let exe = build("seq_patch", "sample_programs/library/seq_patch.lani");
    let work = common::TempArtifact::new("laniusc_patchset", "oracle", None);
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "patchset oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root.join("tests/fixtures/extended/patchset_oracle.py"))
            .arg(exe.path())
            .arg(work.path())
            .arg("300")
            .arg("2"),
        Duration::from_secs(240),
    );
    let _ = std::fs::remove_dir_all(work.path());
    assert!(
        output.status.success() && output.stdout.ends_with(b"failures: 0\n"),
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}
