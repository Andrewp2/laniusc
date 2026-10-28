//! Bounded products/quotients: exact contracts and an independent rational oracle.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn compile(name: &'static str) -> common::TempArtifact {
    let entry = root()
        .join("tests/fixtures/extended_library/statistics_scaling")
        .join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("statistics scaling", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("statistics scaling {name}: {error}"));
    let executable = common::TempArtifact::new("laniusc_statistics_scaling", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

#[test]
fn exact_dyadic_cancellation_validated_domains_and_signed_zero_across_all_arities() {
    let executable = compile("contracts");
    let output = common::process_output_with_timeout(
        "statistics scaling exact contracts",
        &mut Command::new(executable.path()),
        Duration::from_secs(10),
    );
    common::assert_command_success("statistics scaling exact contracts", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn exact_fraction_oracle_for_extreme_exponents_subnormals_and_finite_product_rounding() {
    let executable = compile("model");
    let output = common::process_output_with_timeout(
        "statistics scaling independent Fraction oracle",
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/extended_library/statistics_scaling/oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(35),
    );
    common::assert_command_success("statistics scaling independent Fraction oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.contains("statistics-scaling cases=") && summary.contains("arities=6"),
        "{summary}"
    );
    assert!(summary.contains("max-observed-ULP"), "{summary}");
    eprint!("{summary}");
}
