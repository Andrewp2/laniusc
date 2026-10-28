//! Exact weighted references, atomic contracts and binary64 boundary behavior.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/extended_library/weighted_statistics")
        .join(name)
}
fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = fixture(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let label = name.to_owned();
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("weighted statistics {label}: {error}"));
    let executable = common::TempArtifact::new("laniusc_weighted_statistics", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

#[test]
fn weighted_exact_fraction_decimal_models_cover_merge_trees_scales_and_extreme_weights() {
    let executable = executable("model.lani");
    let output = common::process_output_with_timeout(
        "weighted statistics Fraction and Decimal oracle",
        Command::new("python3")
            .arg("-B")
            .arg(fixture("oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(60),
    );
    common::assert_command_success("weighted statistics exact numerical oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with("weighted-statistics cases="),
        "{summary}"
    );
    assert!(
        summary.contains("layouts=2 exact=Fraction derived=Decimal seed=0x57e12026"),
        "{summary}"
    );
    eprint!("{summary}");
}

#[test]
fn weighted_zero_validation_atomic_views_count_limits_and_subnormal_effective_count_execute() {
    let executable = executable("contracts.lani");
    let events = common::TempArtifact::new("laniusc_weighted_statistics", "allocations", None);
    let output = common::process_output_with_timeout(
        "weighted statistics public and allocation contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(events.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(12),
    );
    common::assert_command_success("weighted statistics public contracts", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let events = fs::read_to_string(events.path()).unwrap();
    assert!(
        events.is_empty(),
        "exercised weighted operations allocate nothing: {events}"
    );
}

#[test]
fn exact_reference_controls_reject_frequency_variance_and_rounded_norm_mistakes() {
    let output = common::process_output_with_timeout(
        "weighted statistics independent reference controls",
        Command::new("python3")
            .arg("-B")
            .arg(fixture("oracle.py"))
            .arg("--self-test"),
        Duration::from_secs(10),
    );
    common::assert_command_success("weighted statistics reference controls", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        output.stdout,
        b"weighted-statistics reference controls=5 wrong-answer-rejections=4\n"
    );
}
