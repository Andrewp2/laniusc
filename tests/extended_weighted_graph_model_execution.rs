//! Weighted shortest paths against exhaustive simple-path and cycle witnesses.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

#[test]
fn weighted_shortest_paths_match_independent_integer_path_and_cycle_enumeration() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/extended/weighted_graph");
    let entry = fixtures.join("model.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("weighted graph path model", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("weighted graph model: {error}"));
    let executable = common::TempArtifact::new("laniusc_weighted_graph_model", "model", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "independent weighted path and cycle reference",
        Command::new("python3")
            .args(["-I", "-B"])
            .arg(fixtures.join("oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(70),
    );
    common::assert_command_success("weighted graph model", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(summary, "weighted-graph-model cases=2819 algorithms=5638 finite=4910 negative_edges=445 negative_cycles=283 controls=12 seed=0x6a90261107\n");
    eprint!("{summary}");
}
