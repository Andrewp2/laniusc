//! Lazy insertion returns recoverable owners under reached allocation failures.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn run(family: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_lazy_map/resources");
    let entry = fixtures.join(format!("{family}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixtures.clone()],
    };
    let bytes = common::run_gpu_codegen_with_timeout("lazy map owner recovery", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry,
                &roots,
                &Default::default(),
            ),
        )
    })
    .unwrap_or_else(|error| panic!("{family} lazy map owners: {error}"));
    let executable = common::TempArtifact::new("laniusc_lazy_map_owners", family, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "lazy map ownership and reached OOM oracle",
        Command::new("python3")
            .args(["-I", "-B"])
            .arg(fixtures.join("oracle.py"))
            .arg(executable.path())
            .arg(family),
        Duration::from_secs(35),
    );
    common::assert_command_success("lazy map owner recovery", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        String::from_utf8(output.stdout).unwrap().trim(),
        format!("lazy-map-{family}-owners cases=5 reached=4 recovered=4 balanced=yes")
    );
}

#[test]
fn lazy_hash_map_returns_candidates_and_recovers_each_reached_allocation_failure() {
    run("hash");
}
#[test]
fn lazy_tree_map_returns_candidates_and_recovers_each_reached_allocation_failure() {
    run("tree");
}
