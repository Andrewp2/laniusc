//! Native worker lifetime, retryable pool retirement, and synchronous failure.
#![cfg(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))]
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
fn probe() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let shim = common::TempArtifact::new("thread_pool_lifecycle", "thread_probe", Some("o"));
        let built = common::process_output_with_timeout(
            "thread pool fault shim",
            Command::new("cc")
                .args([
                    "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fPIC", "-c",
                ])
                .arg(root().join("tests/fixtures/stdlib_thread_lifecycle/thread_probe.c"))
                .arg("-o")
                .arg(shim.path()),
            Duration::from_secs(20),
        );
        common::assert_command_success("thread pool fault shim", &built);
        let entry = root().join("tests/fixtures/stdlib_thread_pool_lifecycle/probe.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![],
        };
        let options = laniusc_compiler::compiler::NativeLinkOptions {
            objects: vec![shim.path().to_path_buf()],
            libraries: vec!["dl".into(), "atomic".into()],
            ..Default::default()
        };
        let bytes = common::run_gpu_codegen_with_timeout("thread pool lifecycle", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry, &roots, &options,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("thread pool lifecycle: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let artifact = common::TempArtifact::new("thread_pool_lifecycle", "probe", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn gate(group: &str) {
    let output = common::process_output_with_timeout(
        format!("thread pool {group}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_thread_pool_lifecycle/oracle.py"))
            .arg(group)
            .arg(probe().path()),
        Duration::from_secs(80),
    );
    common::assert_command_success(format!("thread pool {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let receipt = String::from_utf8(output.stdout).unwrap();
    let count: usize = receipt
        .trim()
        .strip_prefix(&format!("thread-pool group={group} cases="))
        .unwrap_or_else(|| panic!("missing pool receipt: {receipt}"))
        .parse()
        .unwrap();
    assert!(count > 0, "{receipt}");
    print!("{receipt}");
}
#[test]
fn thread_pool_real_workers_match_exact_tasks_map_ordered_reduce_and_scan() {
    gate("model");
}
#[test]
fn thread_pool_partial_start_and_failed_shutdown_retain_retry_authority() {
    gate("lifecycle");
}
#[test]
fn thread_pool_admission_is_checked_before_workers_start() {
    gate("admission");
}
#[test]
fn thread_pool_reached_allocation_failures_balance_exact_source_extents() {
    gate("resources");
}
#[test]
fn thread_pool_failed_synchronous_join_traps_before_borrowed_storage_retirement() {
    gate("traps");
}
#[test]
fn thread_pool_resource_observer_rejects_invalid_ownership_traces() {
    let output = common::process_output_with_timeout(
        "thread pool resource controls",
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_thread_pool_lifecycle/resource_controls.py")),
        Duration::from_secs(10),
    );
    common::assert_command_success("thread pool resource controls", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout, b"thread-pool resource controls=31\n");
}
