#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn compile(name: &str) -> common::TempArtifact {
    let entry = root()
        .join("tests/fixtures/extended_library/higher_statistics")
        .join(format!("{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let label = name.to_owned();
    let bytes = common::run_gpu_codegen_with_timeout("higher descriptive statistics", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("higher statistics {label}: {error}"));
    let executable = common::TempArtifact::new("laniusc_higher_statistics", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

#[test]
fn centered_fraction_decimal_references_cover_higher_moments_and_all_merge_shapes() {
    let executable = compile("model");
    let output = common::process_output_with_timeout(
        "higher moments exact centered Fraction/Decimal oracle",
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/extended_library/higher_statistics/oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(40),
    );
    common::assert_command_success("higher moments exact centered oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with("higher-statistics cases=1212 datasets=51 storage_forms=2 modes=8"),
        "{summary}"
    );
    eprint!("{summary}");
}

#[test]
fn higher_moment_errors_are_atomic_and_borrowed_views_need_no_allocation() {
    let executable = compile("contracts");
    let trace = common::TempArtifact::new("laniusc_higher_statistics", "trace", None);
    let output = common::process_output_with_timeout(
        "higher moments atomic/count/borrow contracts with all allocations denied",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(executable.path()),
        Duration::from_secs(10),
    );
    common::assert_command_success("higher moments atomic/count/borrow contracts", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        !events.contains("mmap(") && !events.contains("munmap("),
        "{events}"
    );
}
