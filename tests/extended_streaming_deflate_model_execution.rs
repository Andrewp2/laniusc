//! Independent zlib decoding, RFC block-policy inspection and byte-event progress.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/extended_streaming_deflate_model")
        .join(name)
}

#[test]
fn streaming_deflate_matches_zlib_block_policy_progress_and_chunk_invariance() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = fixture("model.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("streaming DEFLATE model", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("streaming DEFLATE model: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_streaming_deflate_model", "model", None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "zlib, RFC block policy and streaming byte-event model",
        Command::new("python3")
            .arg("-B")
            .arg(fixture("oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(90),
    );
    common::assert_command_success("independent streaming DEFLATE model", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(
        summary,
        "streaming-deflate-model cases=112 passes=260 patterns=28 whole=112 irregular=112 bytewise=36 input_bytes=5934732 formats=4 layouts=8 seed=0xdef1a7e0261115\n"
    );
    eprint!("{summary}");
}
