//! Reactive scheduling/lifetime contracts and an independent full-evaluation model.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

#[test]
fn reactive_graph_contracts_model_and_sparse_work() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/extended/reactive/graph.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("reactive graph", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("reactive graph: {error}"));
    let exe = common::TempArtifact::new("reactive_graph", "contracts", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "reactive graph contracts, 1000 model batches, sparse 100/1000/10000 sources",
        &mut Command::new(exe.path()),
        Duration::from_secs(15),
    );
    common::assert_command_success("reactive graph execution", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
