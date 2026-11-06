//! Exact integer weighted-graph contracts and checked admission.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn execute(name: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended/weighted_graph")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("weighted graph contracts", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let executable = common::TempArtifact::new("laniusc_weighted_graph", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        name,
        &mut Command::new(executable.path()),
        Duration::from_secs(15),
    );
    common::assert_command_success(name, &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn weighted_graphs_preserve_parallel_edges_exact_costs_paths_and_error_policy() {
    execute("contracts.lani");
}

#[test]
fn weighted_graphs_validate_descriptors_and_admit_limits_before_backing_reads() {
    execute("preflight.lani");
}
