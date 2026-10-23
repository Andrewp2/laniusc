#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, process::Command};

// These are successful map controls for the minimized generic set blockers in
// fixtures/stdlib_compiler_state/owned_sets. No production owned set is claimed.
#[test]
fn owned_set_underlying_map_controls_execute() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for name in ["owned_sets_hash_map_control", "owned_sets_tree_map_control"] {
        let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("{name}: {error}"));
        let exe = common::TempArtifact::new("laniusc_owned_sets", name, None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        let output = common::short_process_output_with_timeout(name, &mut Command::new(exe.path()));
        assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{name}: {output:?}"
        );
    }
}
