//! Canonical CSR validation, publication and explicit owner failure contracts.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Stdio},
    time::{Duration, Instant},
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended_library/sparse")
        .join(name);
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
    .unwrap_or_else(|error| panic!("sparse {label}: {error}"));
    assert!(
        bytes.starts_with(b"\x7fELF"),
        "strict native producer: {name}"
    );
    let executable = common::TempArtifact::new("laniusc_sparse_contract", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

struct Run {
    allocations: usize,
    marker: Vec<u8>,
    injected: usize,
}

fn run(
    executable: &common::TempArtifact,
    operation: Option<u8>,
    denial: Option<usize>,
    deadline: Instant,
) -> Run {
    let events = common::TempArtifact::new("laniusc_sparse_contract", "allocation_trace", None);
    let input = common::TempArtifact::new("laniusc_sparse_contract", "operation", None);
    let mut command = Command::new("strace");
    command.args(["-qq", "-o"]).arg(events.path()).args([
        "-e",
        "trace=mmap,mremap,munmap,brk",
        "-e",
        "signal=none",
    ]);
    if let Some(at) = denial {
        command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={at}")]);
    }
    command.arg(executable.path());
    if let Some(operation) = operation {
        input.write_bytes([operation]);
        command.stdin(fs::File::open(input.path()).unwrap());
    } else {
        command.stdin(Stdio::null());
    }
    let remaining = deadline
        .checked_duration_since(Instant::now())
        .expect("sparse test group exceeded 85 seconds");
    let output = common::process_output_with_timeout(
        format!("sparse operation {operation:?}, allocation denial {denial:?}"),
        &mut command,
        remaining.min(Duration::from_secs(8)),
    );
    common::assert_command_success("sparse native contract", &output);
    assert!(output.stdout.is_empty(), "{output:?}");
    let trace = fs::read_to_string(events.path()).unwrap();
    let mut live = BTreeMap::new();
    let mut allocations = 0;
    let mut injected = 0;
    for line in trace.lines() {
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let size: usize = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let result = line.rsplit_once(" = ").unwrap().1.trim();
            if result.starts_with("-1 ") {
                assert!(
                    result.contains("ENOMEM") && result.contains("INJECTED"),
                    "{trace}"
                );
                injected += 1;
            } else {
                assert!(result.starts_with("0x"), "{trace}");
                assert!(live.insert(result.to_owned(), size).is_none(), "{trace}");
                allocations += 1;
            }
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let (address, size) = arguments.split_once(',').unwrap();
            assert_eq!(
                live.remove(address.trim()),
                Some(size.trim().parse().unwrap()),
                "matching address and size: {trace}"
            );
            assert_eq!(result.trim(), "= 0", "{trace}");
        } else {
            panic!("unexpected allocation service: {line}");
        }
    }
    assert!(live.is_empty(), "unreleased owners: {live:?}\n{trace}");
    Run {
        allocations,
        marker: output.stderr,
        injected,
    }
}

#[test]
fn canonical_metadata_bounds_work_and_matvec_prefix_contracts_execute_without_allocation() {
    let deadline = Instant::now() + Duration::from_secs(85);
    let executable = executable("contracts.lani");
    let result = run(&executable, None, None, deadline);
    assert_eq!(result.allocations, 0);
    assert_eq!(result.injected, 0);
    assert!(result.marker.is_empty());
}

#[test]
fn independent_csr_owners_zero_shapes_duplicates_arithmetic_and_failure_cleanup_execute() {
    let deadline = Instant::now() + Duration::from_secs(85);
    let executable = executable("owners.lani");
    let result = run(&executable, Some(0), None, deadline);
    assert!(result.allocations > 0, "exercise actual owners");
    assert_eq!(result.injected, 0);
    assert!(result.marker.is_empty());
}

fn denials(operations: std::ops::RangeInclusive<u8>) {
    let deadline = Instant::now() + Duration::from_secs(85);
    let executable = executable("owners.lani");
    let mut reached = 0;
    for operation in operations {
        let baseline = run(&executable, Some(operation), None, deadline);
        assert_eq!(baseline.marker, b"S");
        assert!(baseline.allocations > 0 && baseline.injected == 0);
        let mut operation_failures = 0;
        for at in 1..=baseline.allocations {
            let result = run(&executable, Some(operation), Some(at), deadline);
            assert_eq!(
                result.injected, 1,
                "operation {operation}, attempted mmap {at}"
            );
            if result.marker == b"F" {
                operation_failures += 1;
            } else {
                assert!(
                    operation == 5 && result.marker == b"I",
                    "operation {operation}, mmap {at}, marker {:?}",
                    result.marker
                );
            }
        }
        assert!(
            operation_failures > 0,
            "reach operation {operation}, not only its input-owner setup"
        );
        reached += operation_failures;
    }
    eprintln!(
        "sparse reached operation-allocation failures={reached}; all observed mappings matched explicit releases"
    );
}

#[test]
fn every_observed_constructor_clone_and_merge_allocation_denial_preserves_inputs_and_releases_owners()
 {
    denials(1..=7);
}

#[test]
fn every_observed_scale_product_and_dense_conversion_allocation_denial_releases_owners() {
    denials(8..=14);
}
