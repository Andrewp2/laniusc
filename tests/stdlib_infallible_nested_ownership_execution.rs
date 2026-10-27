//! Ordinary nested adapters with actual String owners and pre-exit accounting.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn probe() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root
            .join("tests/fixtures/stdlib_execution/infallible_nested_iteration_owners/probe.lani");
        let stdlib = root.join("stdlib");
        let bytes =
            common::run_gpu_codegen_with_timeout("ordinary nested iterator owners", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(
                        &entry, &stdlib,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("ordinary nested iterator owner probe: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let artifact =
            common::TempArtifact::new("laniusc_infallible_nested_iteration_owners", "probe", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

#[test]
fn ordinary_nested_owned_strings_retire_and_resume_without_allocating() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "ordinary nested iterator ownership oracle",
        Command::new("python3")
            .arg("-B")
            .arg(root.join(
                "tests/fixtures/stdlib_execution/infallible_nested_iteration_owners/oracle.py",
            ))
            .arg(probe().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success("ordinary nested iterator ownership oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII finite receipt");
    let receipts: Vec<&str> = summary
        .lines()
        .filter(|line| line.starts_with("PASS infallible-nested-owners "))
        .collect();
    assert_eq!(
        receipts,
        ["PASS infallible-nested-owners cases=8 reached-oom=0"],
        "{summary}"
    );
    print!("{summary}");
}
