#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};
fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_unicode_sentences", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[test]
fn generated_sentence_tables_match_pinned_official_unicode_17() {
    let result = common::process_output_with_timeout(
        "sentence table regeneration",
        Command::new("python3")
            .args(["tools/generate_unicode_sentences.py", "--check"])
            .current_dir(env!("CARGO_MANIFEST_DIR")),
        Duration::from_secs(10),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
}
#[test]
fn complete_sentence_conformance_slow_rule_oracle_and_linear_lookahead_without_allocation() {
    let exe = executable("tests/fixtures/extended/unicode_sentences_input.lani");
    let result = common::process_output_with_timeout(
        "Unicode 17 official sentence corpus and independent slow rule model",
        Command::new("python3")
            .args([
                "-c",
                include_str!("fixtures/extended/unicode_sentences_oracle.py"),
            ])
            .arg(exe.path())
            .current_dir(env!("CARGO_MANIFEST_DIR")),
        Duration::from_secs(50),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
}
#[test]
fn sentence_views_copies_bounds_work_limits_and_manual_backing_contracts() {
    let exe = executable("tests/fixtures/extended/unicode_sentences_contracts.lani");
    let result = common::process_output_with_timeout(
        "sentence cursor contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
    assert!(
        result.stdout.is_empty() && result.stderr.is_empty(),
        "{result:?}"
    );
}
