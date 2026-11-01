//! core::search and Text::find against Python bytes/str search on generated cases.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

#[test]
fn search_matches_python_on_generated_cases() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let relative = "tests/fixtures/stdlib_execution/search/cases.lani";
    let entry = root.join(relative);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(relative, move || {
        pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .unwrap_or_else(|error| panic!("{relative}: {error}"));
    let runner = common::TempArtifact::new("laniusc_search", "cases", None);
    runner.write_bytes(bytes);
    std::fs::set_permissions(runner.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    for seed in ["1", "2", "3"] {
        let output = common::process_output_with_timeout(
            "search oracle",
            Command::new("python3")
                .arg("-I")
                .arg(root.join("tests/fixtures/stdlib_execution/search/oracle.py"))
                .arg(runner.path())
                .arg(seed)
                .arg("20000"),
            Duration::from_secs(120),
        );
        common::assert_command_success("search oracle", &output);
        let summary = String::from_utf8(output.stdout).unwrap();
        assert!(summary.starts_with("search cases=20000 mismatches=0 "), "{summary}");
    }
}
