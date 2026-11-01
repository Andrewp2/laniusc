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
    let exe = common::TempArtifact::new("laniusc_textutils", label, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn available(tool: &str) -> bool {
    Command::new(tool).arg("--version").output().map(|o| o.status.success()).unwrap_or(false)
}

// Build sample_programs/library/text_TOOL.lani and run its oracle
// (tests/fixtures/extended/TOOL_oracle.py) against GNU TOOL under LC_ALL=C:
// every generated case must match stdout (or the output file) and status.
fn oracle(tool: &str, cases: &str) {
    if !available(tool) || !available("python3") {
        eprintln!("skipping: GNU {tool} and python3 are required");
        return;
    }
    let exe = build(&format!("text_{tool}"), &format!("sample_programs/library/text_{tool}.lani"));
    let work = common::TempArtifact::new("laniusc_textutils", &format!("{tool}_oracle"), None);
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        &format!("{tool} oracle"),
        Command::new("python3")
            .arg("-I")
            .arg(root.join(format!("tests/fixtures/extended/{tool}_oracle.py")))
            .arg(exe.path())
            .arg(work.path())
            .arg(cases),
        Duration::from_secs(280),
    );
    let _ = std::fs::remove_dir_all(work.path());
    assert!(
        output.status.success() && output.stdout.ends_with(b"failures: 0\n"),
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn text_wc_matches_gnu_wc() {
    oracle("wc", "600");
}

#[test]
fn text_tr_matches_gnu_tr() {
    oracle("tr", "600");
}

#[test]
fn text_cut_matches_gnu_cut() {
    oracle("cut", "600");
}

#[test]
fn text_uniq_matches_gnu_uniq() {
    oracle("uniq", "600");
}

#[test]
fn text_sort_matches_gnu_sort() {
    oracle("sort", "400");
}
