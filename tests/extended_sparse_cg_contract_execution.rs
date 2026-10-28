//! Sparse CG stopping, requested work admission and workspace owner cleanup.
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
        .join("tests/fixtures/extended_library/sparse_cg")
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
    .unwrap_or_else(|error| panic!("sparse CG {label}: {error}"));
    assert!(bytes.starts_with(b"\x7fELF"), "strict native producer");
    let executable = common::TempArtifact::new("laniusc_sparse_cg", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

struct Run {
    allocations: usize,
    injected: usize,
    marker: Vec<u8>,
}

fn run(
    executable: &common::TempArtifact,
    operation: Option<u8>,
    denial: Option<usize>,
    deadline: Instant,
) -> Run {
    let events = common::TempArtifact::new("laniusc_sparse_cg", "trace", None);
    let input = common::TempArtifact::new("laniusc_sparse_cg", "operation", None);
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
        .expect("sparse CG group exceeded 85 seconds");
    let output = common::process_output_with_timeout(
        format!("sparse CG operation {operation:?}, mmap denial {denial:?}"),
        &mut command,
        remaining.min(Duration::from_secs(8)),
    );
    common::assert_command_success("sparse CG native contract", &output);
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
                "matched address and size: {trace}"
            );
            assert_eq!(result.trim(), "= 0", "{trace}");
        } else {
            panic!("unexpected allocation service: {line}");
        }
    }
    assert!(
        live.is_empty(),
        "unreleased sparse CG owners: {live:?}\n{trace}"
    );
    Run {
        allocations,
        injected,
        marker: output.stderr,
    }
}

#[test]
fn cg_semantic_contracts_execute_with_truthful_fresh_residuals_and_explicit_errors() {
    let deadline = Instant::now() + Duration::from_secs(85);
    let executable = executable("contracts.lani");
    let result = run(&executable, None, None, deadline);
    assert!(result.allocations > 0 && result.injected == 0 && result.marker.is_empty());
}

#[test]
fn cg_requested_budget_metadata_and_system_rejections_allocate_nothing() {
    let deadline = Instant::now() + Duration::from_secs(85);
    let executable = executable("owners.lani");
    let result = run(&executable, Some(0), None, deadline);
    assert_eq!(result.allocations, 0);
    assert_eq!(result.injected, 0);
    assert_eq!(result.marker, b"P");
}

fn denials(operations: std::ops::RangeInclusive<u8>) {
    let deadline = Instant::now() + Duration::from_secs(85);
    let executable = executable("owners.lani");
    let mut reached = 0;
    for operation in operations {
        let baseline = run(&executable, Some(operation), None, deadline);
        let expected = match operation {
            2 => b"RL",
            4 => b"RN",
            _ => b"RC",
        };
        assert_eq!(baseline.marker, expected);
        assert!(baseline.allocations > 0 && baseline.injected == 0);
        for at in 1..=baseline.allocations {
            let result = run(&executable, Some(operation), Some(at), deadline);
            assert_eq!(
                result.marker, b"RF",
                "reached selected operation {operation}, mmap {at}"
            );
            assert_eq!(result.injected, 1);
            reached += 1;
        }
    }
    eprintln!(
        "sparse-cg reached workspace allocation denials={reached}; each mapping matched an explicit address/size release"
    );
}

#[test]
fn cg_converged_and_exhausted_workspace_allocation_denials_release_every_owner() {
    denials(1..=3);
}

#[test]
fn cg_numerical_and_tiny_jacobi_workspace_allocation_denials_release_every_owner() {
    denials(4..=5);
}
