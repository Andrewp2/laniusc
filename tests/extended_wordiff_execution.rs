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
    let exe = common::TempArtifact::new("laniusc_wordiff", label, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn available(tool: &str) -> bool {
    Command::new(tool).arg("--version").output().map(|o| o.status.success()).unwrap_or(false)
}

#[test]
fn wordiff_api_contracts() {
    let exe = build("contracts", "tests/fixtures/extended/wordiff_contracts.lani");
    let output = common::process_output_with_timeout(
        "wordiff contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(30),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}

// Generated pairs and repositories: exact agreement with git diff
// --word-diff=plain, --word-diff-regex=., --stat and git diff --stat over
// git and diff -ruN patches, including repeated-word and heuristic cases.
#[test]
fn seq_diff_word_and_stat_match_git() {
    if !available("git") || !available("diff") || !available("python3") {
        eprintln!("skipping: git, GNU diff and python3 are required");
        return;
    }
    let diff = build("seq_diff", "sample_programs/library/seq_diff.lani");
    let stat = build("seq_diffstat", "sample_programs/library/seq_diffstat.lani");
    let work = common::TempArtifact::new("laniusc_wordiff", "oracle", None);
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "wordiff oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root.join("tests/fixtures/extended/wordiff_oracle.py"))
            .arg(diff.path())
            .arg(stat.path())
            .arg(work.path())
            .arg("400")
            .arg("--strict-repeated"),
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

// Generated pairs (distinct, repeated, indented code, C-like functions,
// >64-repeat fallback ranges, mixed and large): seq-diff's default, --histogram
// and -W output and status equal plain git diff --no-index (indent heuristic,
// hunk-header function names) from the first hunk header on.
#[test]
fn seq_diff_matches_git_diff() {
    if !available("git") || !available("python3") {
        eprintln!("skipping: git and python3 are required");
        return;
    }
    let diff = build("seq_diff_git", "sample_programs/library/seq_diff.lani");
    let work = common::TempArtifact::new("laniusc_wordiff", "gitdiff", None);
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "git diff oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root.join("tests/fixtures/extended/git_diff_oracle.py"))
            .arg(diff.path())
            .arg(work.path())
            .arg("1200"),
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
