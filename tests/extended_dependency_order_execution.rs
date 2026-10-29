//! Independent exhaustive ordering and shortest-path models for the CSV app.
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
        let entry = root().join("sample_programs/library/dependency_order.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout(
            "directed dependency order application",
            move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            },
        )
        .unwrap_or_else(|error| panic!("dependency order: {error}"));
        assert!(
            common::x86_jumps::is_x86_64_executable(&bytes),
            "dependency order must produce an actual little-endian ELF64 x86-64 executable"
        );
        let artifact = common::TempArtifact::new("dependency_order", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("dependency order {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/extended_execution/dependency_order/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("dependency order {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("dependency-order-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn dependency_order_exhaustive_small_orders_shortest_paths_and_scale_match_reference() {
    oracle("model", 83);
}
#[test]
fn dependency_order_cycles_csv_bounds_and_exact_eof_reject_before_publication() {
    oracle("rejection", 40);
}
#[test]
fn dependency_order_cli_help_and_option_limits_execute() {
    oracle("cli", 41);
}
#[test]
fn dependency_order_reached_owner_failures_io_prefix_and_cleanup_execute() {
    oracle("io", 19);
}
