//! Exact cardinalities, lazy queries, sequence models and explicit owner recovery.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output},
    time::Duration,
};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/exact_size_iterators")
        .join(name)
}

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = fixture(name);
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

fn executable(name: &str) -> common::TempArtifact {
    let bytes = compile(name).unwrap_or_else(|error| panic!("exact count {name}: {error}"));
    let executable = common::TempArtifact::new("laniusc_exact_size", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

fn success(output: &Output) {
    common::assert_command_success("exact-size iterator runtime", output);
    assert!(output.stderr.is_empty(), "{output:?}");
}

fn trace(name: &str) -> String {
    let executable = executable(name);
    let events = common::TempArtifact::new("laniusc_exact_size", "allocations", None);
    let output = common::process_output_with_timeout(
        "exact-size iterator allocation contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(events.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(12),
    );
    success(&output);
    assert!(output.stdout.is_empty(), "{output:?}");
    fs::read_to_string(events.path()).unwrap()
}

#[test]
fn metadata_queries_are_lazy_exact_and_allocation_free_at_integer_limits() {
    let events = trace("contracts.lani");
    assert!(events.is_empty(), "pure cardinality operations: {events}");
}

#[test]
fn collection_counts_follow_transfers_and_explicit_recovery_without_retained_storage() {
    let events = trace("collections.lani");
    let mut live = BTreeMap::<String, usize>::new();
    let mut allocations = 0;
    for line in events.lines() {
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let size = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let address = line.rsplit_once(" = ").unwrap().1.trim();
            assert!(address.starts_with("0x"), "source allocation: {events}");
            assert!(live.insert(address.to_owned(), size).is_none(), "{events}");
            allocations += 1;
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let (address, size) = arguments.split_once(',').unwrap();
            assert_eq!(
                live.remove(address.trim()),
                Some(size.trim().parse().unwrap()),
                "matching explicit release: {events}"
            );
            assert_eq!(result.trim(), "= 0", "{events}");
        } else {
            panic!("unexpected allocation service: {line}");
        }
    }
    assert!(allocations > 0, "exercise real collection owners");
    assert!(live.is_empty(), "no retained backing: {events}");
}

#[test]
fn independent_sequence_models_match_values_counts_and_query_effects() {
    let executable = executable("model.lani");
    let output = common::process_output_with_timeout(
        "exact-size independent sequence reference",
        Command::new("python3")
            .arg("-B")
            .arg(fixture("oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(60),
    );
    success(&output);
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with("exact-size-iterators cases="),
        "{summary}"
    );
    eprint!("{summary}");
}

#[test]
fn exact_size_requires_matching_capabilities_and_excludes_unrepresentable_compositions() {
    for name in [
        "negative_missing_exact.lani",
        "negative_wrong_item.lani",
        "negative_filter.lani",
        "negative_chain.lani",
        "negative_zip.lani",
    ] {
        let error = compile(name).expect_err("this source has no matching exact-size capability");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic.primary_label.expect("rejected exact-size use");
        assert!(label.path.ends_with(name), "{label:?}");
        assert!(
            label
                .source_line
                .as_deref()
                .unwrap_or("")
                .contains("require_exact"),
            "{label:?}"
        );
    }
}
