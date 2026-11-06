//! Current-runtime source ownership under reached weighted-graph allocation failures.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

#[test]
fn weighted_graph_owners_release_partial_results_and_recover_each_reached_allocation_failure() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/extended/weighted_graph");
    let entry = fixtures.join("resources.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("weighted graph owner recovery", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry,
                &roots,
                &Default::default(),
            ),
        )
    })
    .unwrap_or_else(|error| panic!("weighted graph owners: {error}"));
    let executable = common::TempArtifact::new("laniusc_weighted_graph_owners", "owners", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "weighted graph reached allocation failure oracle",
        Command::new("python3")
            .args(["-I", "-B"])
            .arg(fixtures.join("resource_oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(70),
    );
    common::assert_command_success("weighted graph owners", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with("weighted-graph-owners profiles=5 reached="),
        "{summary}"
    );
    assert!(
        summary.ends_with(" balanced=yes recovered=yes\n"),
        "{summary}"
    );
    eprint!("{summary}");
}
