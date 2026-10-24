#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};
fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_discrete", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[test]
fn high_precision_mass_tails_and_independent_sampling_models() {
    let exe = executable("tests/fixtures/extended/discrete_model.lani");
    for (label, script) in [
        (
            "discrete high precision models",
            include_str!("fixtures/extended/discrete_oracle.py"),
        ),
        (
            "discrete sampling models",
            include_str!("fixtures/extended/discrete_sampling_oracle.py"),
        ),
    ] {
        let output = common::process_output_with_timeout(
            label,
            Command::new("python3").args(["-c", script]).arg(exe.path()),
            Duration::from_secs(40),
        );
        assert_eq!(output.status.code(), Some(0), "{label}: {output:?}");
        println!("{label}: {}", String::from_utf8_lossy(&output.stdout));
    }
}
#[test]
fn generic_sources_exact_cumulative_budgets_errors_and_no_allocation() {
    let admission = executable("tests/fixtures/extended/discrete_admission.lani");
    let output = common::short_process_output_with_timeout(
        "discrete generic admission",
        &mut Command::new(admission.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let exe = executable("tests/fixtures/extended/discrete_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_discrete", "trace", None);
    let output = common::process_output_with_timeout(
        "discrete budget/source contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}
