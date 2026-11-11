//! Isolate item-import type selection from weighted-graph runtime behavior.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;

use std::{path::PathBuf, time::Duration};

fn execute(fixture: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_compiler_state/weighted_view_import")
        .join(fixture);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("weighted View item import", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry,
                &roots,
                &Default::default(),
            ),
        )
    })
    .unwrap_or_else(|error| panic!("{fixture}: {error}"));
    let executable = common::TempArtifact::new("weighted_view_import", fixture, None);
    executable.write_bytes(bytes);
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        fixture,
        &mut std::process::Command::new(executable.path()),
        Duration::from_secs(15),
    );
    common::assert_command_success(fixture, &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn weighted_view_qualified_return_executes() {
    execute("qualified.lani");
}

#[test]
fn weighted_view_item_import_without_collision_executes() {
    execute("no_collision.lani");
}

#[test]
#[ignore = "confirmed View item-import compiler dependency; intended-success regression awaits repair"]
fn weighted_view_item_import_beats_colliding_module_type() {
    execute("selected.lani");
}
