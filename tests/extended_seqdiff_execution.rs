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
    let exe = common::TempArtifact::new("laniusc_seqdiff", label, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn available(tool: &str) -> bool {
    Command::new(tool).arg("--version").output().map(|o| o.status.success()).unwrap_or(false)
}

#[test]
fn seqdiff_api_contracts() {
    let exe = build("contracts", "tests/fixtures/extended/seqdiff_contracts.lani");
    let output = common::process_output_with_timeout(
        "seqdiff contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(30),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}

// Generated file pairs: minimality against an O(N*M) LCS, round trips through
// GNU patch and seq_patch, real GNU diff -u input, and offset/fuzz agreement
// with GNU patch -F0/-F2 on output bytes and rejected hunk sets.
#[test]
fn seq_diff_and_seq_patch_match_independent_oracles() {
    if !available("diff") || !available("patch") || !available("python3") {
        eprintln!("skipping: GNU diff, GNU patch and python3 are required");
        return;
    }
    let diff = build("seq_diff", "sample_programs/library/seq_diff.lani");
    let patch = build("seq_patch", "sample_programs/library/seq_patch.lani");
    let work = common::TempArtifact::new("laniusc_seqdiff", "oracle", None);
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "seqdiff oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root.join("tests/fixtures/extended/seqdiff_oracle.py"))
            .arg(diff.path())
            .arg(patch.path())
            .arg(work.path())
            .arg("200"),
        Duration::from_secs(240),
    );
    let _ = std::fs::remove_dir_all(work.path());
    assert!(
        output.status.success() && output.stdout.ends_with(b"OK\n"),
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}
