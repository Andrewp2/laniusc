#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};

// Compile the real tgz, compress-bytes and xz-bytes programs, then let
// Python's zlib, gzip, lzma and tarfile act as oracles in both directions
// (tests/fixtures/extended/tgz_oracle.py and xz_oracle.py). The oracle prints exact per-group counts and fails on any
// disagreement, including corrupted streams and hand-built pax records.
fn executable(path: &str, stem: &str) -> common::TempArtifact {
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
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_tgz", stem, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn tgz_and_codecs_agree_with_python_zlib_gzip_and_tarfile() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let tgz = executable("sample_programs/library/tgz.lani", "tgz");
    let codec = executable("sample_programs/library/compress_bytes.lani", "compress-bytes");
    let work = common::TempArtifact::new("laniusc_tgz", "work", None);
    std::fs::create_dir_all(work.path()).unwrap();
    let output = common::process_output_with_timeout(
        "tgz python oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root.join("tests/fixtures/extended/tgz_oracle.py"))
            .arg(tgz.path())
            .arg(codec.path())
            .arg(work.path()),
        Duration::from_secs(240),
    );
    let _ = std::fs::remove_dir_all(work.path());
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let report = String::from_utf8(output.stdout).unwrap();
    assert!(report.contains(" 0 failures"), "{report}");
}

#[test]
fn xz_and_lzma_decoding_agrees_with_python_lzma() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let decoder = executable("sample_programs/library/xz_bytes.lani", "xz-bytes");
    let output = common::process_output_with_timeout(
        "xz python oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root.join("tests/fixtures/extended/xz_oracle.py"))
            .arg(decoder.path())
            .arg("--quick"),
        Duration::from_secs(240),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let report = String::from_utf8(output.stdout).unwrap();
    assert!(report.contains(" 0 failures"), "{report}");
}
