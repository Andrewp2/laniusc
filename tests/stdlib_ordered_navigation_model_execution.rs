//! Ordered navigation and bounded ranges against an independent sorted-list model.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_ordered_navigation/model")
        .join(name)
}

#[test]
fn ordered_navigation_matches_sorted_model_lawful_descents_and_two_ended_ranges() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = fixture("model.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout("ordered navigation model", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("ordered navigation model: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_ordered_navigation_model", "model", None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "independent ordered navigation reference",
        Command::new("python3")
            .arg("-B")
            .arg(fixture("oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(90),
    );
    common::assert_command_success("ordered navigation model", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(
        summary,
        "ordered-navigation-model cases=48 commands=10565 navigations=1005 policy_navigations=1188 ranges=815 policy_ranges=1726 invalid_ranges=295 pulls=20923 back_pulls=5637 policy_calls=7592 descents=2467 checks=799 empty_ranges=1302 equal_runs=49 snapshot_entries=2878 removals=329 removed_entries=1601 extractions=278 extracted_entries=1106 nav_routes=16 range_routes=36 controls=9 seed=0xd0e20261031\n"
    );
    eprint!("{summary}");
}
