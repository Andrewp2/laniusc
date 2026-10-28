//! Checked context ordering and heterogeneous bounds without memory services.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/slice_ordering")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
}

#[test]
fn checked_slice_ordering_preserves_payloads_and_bounds_without_memory_services() {
    let bytes = compile("contracts.lani")
        .unwrap_or_else(|error| panic!("slice ordering contracts: {error}"));
    assert!(bytes.starts_with(b"\x7fELF"), "strict native contracts");
    let executable = common::TempArtifact::new("laniusc_slice_ordering", "contracts", None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let events = common::TempArtifact::new("laniusc_slice_ordering", "allocation_trace", None);
    let output = common::process_output_with_timeout(
        "checked slice metadata, generic payloads, heterogeneous comparison and strided ordering",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(events.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(12),
    );
    common::assert_command_success("slice ordering native contracts", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let events = fs::read_to_string(events.path()).unwrap();
    assert!(
        events.is_empty(),
        "pure algorithms use no memory services: {events}"
    );
}

fn rejected_bounds(names: &[&str]) {
    for &name in names {
        let error = compile(name).expect_err("no matching comparator capability");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic
            .primary_label
            .expect("explicit bounded API use is rejected");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        let line = label.source_line.as_deref().unwrap_or("");
        assert!(
            line.contains("core::slice::") && line.contains("rejected_ordering_bound"),
            "relevant comparator bound use in {name}: {label:?}"
        );
    }
}

#[test]
fn slice_sort_requires_the_matching_comparator_or_natural_ord_capability() {
    rejected_bounds(&[
        "negative_missing_comparator.lani",
        "negative_wrong_left.lani",
        "negative_natural_without_ord.lani",
    ]);
}

#[test]
fn heterogeneous_search_requires_element_then_key_comparator_operands() {
    rejected_bounds(&[
        "negative_wrong_right.lani",
        "negative_reversed_operands.lani",
    ]);
}
