//! The route-cost consumer: exact integers, independent route witnesses and I/O.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/route_cost.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        // Native linking supplies sized source symbols for the existing exact
        // syscall authority verifier. No external graph library is linked.
        let options = laniusc_compiler::compiler::NativeLinkOptions::default();
        let bytes = common::run_gpu_codegen_with_timeout("route-cost application", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("route-cost: {error}"));
        let artifact = common::TempArtifact::new("route_cost", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn oracle(mode: &str) {
    let output = common::process_output_with_timeout(
        format!("route-cost {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/extended/route_cost/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("route-cost {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("route-cost-{mode} cases=")),
        "{summary}"
    );
    assert!(summary.contains(" evidence=executed"), "{summary}");
    eprint!("{summary}");
}

#[test]
fn route_cost_distances_and_routes_match_simple_path_enumeration() {
    oracle("model");
}
#[test]
fn route_cost_admission_arithmetic_and_algorithm_failures_publish_no_prefix() {
    oracle("rejection");
}
#[test]
fn route_cost_cli_help_and_limits_execute() {
    oracle("cli");
}
#[test]
fn route_cost_io_and_three_reached_allocation_denials_release_source_owners() {
    oracle("io");
}
