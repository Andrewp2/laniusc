#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
//! ext::pratt: direct API contracts, and the pratt_calc sample against a
//! CPython `ast` oracle. See docs/extended-pratt.md.
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, time::Duration};

use laniusc_compiler::compiler::{EntrySourceRoots, compile_entry_to_x86_64_with_source_roots};

fn executable(root: &PathBuf, entry: &str, stem: &str) -> common::TempArtifact {
    let entry = root.join(entry);
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(stem, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{stem}: {error}"));
    let exe = common::TempArtifact::new("laniusc_pratt", stem, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn pratt_table_conflicts_event_order_errors_and_capacity_execute() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let exe = executable(&root, "tests/fixtures/extended/pratt_oracle/contracts.lani", "contracts");
    let output = common::short_process_output_with_timeout(
        "pratt contracts",
        &mut std::process::Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}

#[test]
fn pratt_calc_agrees_with_cpython_ast_on_generated_expressions() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let exe = executable(&root, "sample_programs/library/pratt_calc.lani", "pratt_calc");
    let output = common::process_output_with_timeout(
        "pratt Python oracle",
        std::process::Command::new("python3")
            .arg("-I")
            .arg(root.join("tests/fixtures/extended/pratt_oracle/oracle.py"))
            .arg(exe.path()),
        Duration::from_secs(120),
    );
    let report = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success(), "{report}\n{output:?}");
    for line in ["formed 20000/20000", "soup 5000/5000", "disagreements 0"] {
        assert!(report.lines().any(|l| l == line), "missing {line:?} in\n{report}");
    }
}
