#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};

fn executable(name: &str) -> common::TempArtifact {
    let path = format!("tests/fixtures/stdlib_btree_map/{name}.lani");
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(&path);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(&path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_btree_map", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

// model: random edits checked against alloc::tree_map; types: every key and
// value shape; failure: a low RLIMIT_AS fails node growth, which must leave
// the map unchanged; bulk: from_sorted, try_clone and the sinks; set:
// alloc::btree_set against alloc::tree_set, including set algebra.
#[test]
fn btree_map_fixtures_execute() {
    for name in ["model", "types", "failure", "bulk", "set"] {
        let exe = executable(name);
        // model, bulk and failure run for 1-2 s each (hundreds of thousands
        // of checked edits), past the short-process limit.
        let output = common::process_output_with_timeout(
            "btree map",
            &mut Command::new(exe.path()),
            Duration::from_secs(30),
        );
        assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{name}: {output:?}"
        );
    }
}
