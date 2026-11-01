#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};

// Each fixture under tests/fixtures/compiler_defects reproduces a fixed
// compiler defect and exits 0 when compiled correctly.
fn compiles_and_exits_zero(name: &str) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let path = format!("tests/fixtures/compiler_defects/{name}.lani");
    let entry = root.join(&path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout(&path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_compiler_defect", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let out = common::process_output_with_timeout(&path, &mut Command::new(exe.path()), Duration::from_secs(10));
    assert_eq!(out.status.code(), Some(0), "{out:?}");
}

#[test]
fn lnc0047_literal_arm_of_a_nested_match_takes_the_outer_context() {
    compiles_and_exits_zero("lnc0047_nested_match_literal_arm");
}

#[test]
fn b14_self_method_called_through_its_type_path_takes_the_receiver_first() {
    compiles_and_exits_zero("b14_path_self_method_inherent");
}

#[test]
fn b14_bound_self_member_called_through_the_parameter_path_routes() {
    compiles_and_exits_zero("b14_path_self_method_bound");
}
