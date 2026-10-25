#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};
fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/extended/{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let label = name.to_owned();
    let bytes = common::run_gpu_codegen_with_timeout(&label, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_unicode_lines", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[test]
fn pinned_unicode_17_line_data_reproduces_and_hashes_match() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::short_process_output_with_timeout(
        "Unicode line property generation",
        Command::new("python3")
            .arg(root.join("tools/generate_unicode_lines.py"))
            .arg("--check"),
    );
    assert!(output.status.success(), "{output:?}");
}
#[test]
fn full_official_unicode_17_line_conformance_and_long_contexts_without_allocation() {
    let exe = executable("unicode_lines_input");
    let output = common::process_output_with_timeout(
        "full Unicode 17 line conformance",
        Command::new("python3")
            .args([
                "-c",
                include_str!("fixtures/extended/unicode_lines_oracle.py"),
            ])
            .arg(exe.path())
            .arg(env!("CARGO_MANIFEST_DIR")),
        Duration::from_secs(50),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}
#[test]
fn line_cursor_bounds_utf8_limits_forks_and_mandatory_status_contracts() {
    let exe = executable("unicode_lines_contracts");
    let trace = common::TempArtifact::new("laniusc_unicode_lines", "noalloc", None);
    let output = common::short_process_output_with_timeout(
        "line cursor contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
    assert!(std::fs::read(trace.path()).unwrap().is_empty());
}
