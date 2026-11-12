#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

use crate::common;

fn executable(path: &str, stem: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
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
    let exe = common::TempArtifact::new("laniusc_zstd", stem, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn streaming_frames_and_encoders_match_zstd_across_chunk_boundaries() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let decoder = executable("sample_programs/library/unzstd.lani", "unzstd");
    let encoder = executable("sample_programs/library/zstd.lani", "zstd");
    let hash = executable(
        "tests/fixtures/extended/zstd_oracle/xxh64_probe.lani",
        "xxh64",
    );
    let decode_probe = executable(
        "tests/fixtures/extended/zstd_oracle/zstd_probe.lani",
        "decode",
    );
    let encode_probe = executable(
        "tests/fixtures/extended/zstd_oracle/zstd_encode_probe.lani",
        "encode",
    );
    let work = common::TempArtifact::new("laniusc_zstd", "work", None);
    let output = common::process_output_with_timeout(
        "zstd independent streaming oracle",
        Command::new("python3")
            .arg("-I")
            .arg(root.join("tests/fixtures/extended/zstd_oracle/oracle.py"))
            .arg(decoder.path())
            .arg(hash.path())
            .arg(decode_probe.path())
            .arg(work.path())
            .arg("--quick")
            .arg(format!("--zstd={}", encoder.path().display()))
            .arg(format!("--encode-probe={}", encode_probe.path().display())),
        Duration::from_secs(240),
    );
    let _ = std::fs::remove_dir_all(work.path());
    common::assert_command_success("zstd independent streaming oracle", &output);
    let report = String::from_utf8(output.stdout).unwrap();
    assert!(report.contains("failures 0"), "{report}");
}
