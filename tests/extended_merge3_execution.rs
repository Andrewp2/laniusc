#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

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
    let exe = common::TempArtifact::new("laniusc_merge3", label, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn available(tool: &str) -> bool {
    Command::new(tool).arg("--version").output().map(|o| o.status.success()).unwrap_or(false)
}

#[test]
fn merge3_api_contracts() {
    let exe = build("contracts", "tests/fixtures/extended/merge3_contracts.lani");
    let output = common::process_output_with_timeout(
        "merge3 contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(30),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}

// Generated triples: exact output/status agreement with git merge-file (merge
// and diff3 styles) and GNU diff3 -m on distinct-line files, plus merge
// properties on every triple.
#[test]
fn seq_merge_matches_git_merge_file_and_diff3() {
    if !available("git") || !available("diff3") || !available("python3") {
        eprintln!("skipping: git, GNU diff3 and python3 are required");
        return;
    }
    let merge = build("seq_merge", "sample_programs/library/seq_merge.lani");
    let work = common::TempArtifact::new("laniusc_merge3", "oracle", None);
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "merge3 oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root.join("tests/fixtures/extended/merge3_oracle.py"))
            .arg(merge.path())
            .arg(work.path())
            .arg("600"),
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
