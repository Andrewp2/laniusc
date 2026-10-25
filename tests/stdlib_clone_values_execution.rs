//! Opt-in structural cloning: exact scalar bits, active payloads and ownership.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Output},
    time::Duration,
};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_foundation/clone_values");
    let entry = fixtures.join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixtures],
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
}

fn executable(name: &str) -> common::TempArtifact {
    let bytes = compile(name).unwrap_or_else(|error| panic!("clone values {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes), "{name}");
    let file = common::TempArtifact::new("clone_values", name, None);
    file.write_bytes(bytes); // Preserve the common strict ELF/transfer checker.
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}

fn traced(exe: &common::TempArtifact, fail_at: Option<usize>) -> (Output, String) {
    let trace = common::TempArtifact::new("clone_values", "mapping_trace", None);
    let mut command = Command::new("timeout");
    command
        .args(["--kill-after=1s", "3s", "strace", "-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"]);
    if let Some(index) = fail_at {
        command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={index}")]);
    }
    command.arg(exe.path());
    let output = common::process_output_with_timeout(
        "bounded structural clone ownership trace",
        &mut command,
        Duration::from_secs(5),
    );
    (output, fs::read_to_string(trace.path()).unwrap())
}

struct Ledger {
    attempts: Vec<usize>,
    failed: usize,
    messages: usize,
}

fn ledger(trace: &str, owned_messages: bool) -> Ledger {
    let mut live = BTreeMap::<String, usize>::new();
    let mut attempts = Vec::new();
    let mut failed = 0;
    let mut messages = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let size: usize = line.split(',').nth(1).unwrap().trim().parse().unwrap();
            attempts.push(size);
            let address = line
                .rsplit_once(" = ")
                .unwrap()
                .1
                .split_whitespace()
                .next()
                .unwrap();
            if address.starts_with("0x") {
                assert!(live.insert(address.to_owned(), size).is_none(), "{trace}");
            } else {
                assert_eq!(address, "-1", "{trace}");
                assert!(line.contains("ENOMEM"), "{trace}");
                failed += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let (arguments, result) = tail.split_once(')').unwrap();
            let (address, size) = arguments.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            assert_eq!(live.remove(address.trim()), Some(size), "{trace}");
            assert_eq!(result.trim(), "= 0", "{trace}");
            if owned_messages && size == 5 {
                messages += 1;
                assert!(
                    live.is_empty(),
                    "E released before source/fresh/partial owners: {trace}"
                );
            }
        } else {
            panic!("unexpected mapping trace event: {line}");
        }
    }
    assert!(live.is_empty(), "unreleased mapping owners: {trace}");
    Ledger {
        attempts,
        failed,
        messages,
    }
}

fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stdout.is_empty(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn scalar_extremes_unicode_and_ieee_payloads_preserve_exact_values() {
    let exe = executable("scalars.lani");
    let (output, trace) = traced(&exe, None);
    checked(&output, 0);
    let allocations = ledger(&trace, false);
    assert!(
        allocations.attempts.is_empty(),
        "scalar clone allocated: {trace}"
    );
    assert_eq!(allocations.failed, 0);
}

#[test]
fn nested_option_result_pair_and_vec_keep_independent_actual_owners() {
    let exe = executable("nested.lani");
    let (output, trace) = traced(&exe, None);
    checked(&output, 0);
    let allocations = ledger(&trace, false);
    assert!(
        !allocations.attempts.is_empty(),
        "owned String/Vec need backing"
    );
    assert_eq!(allocations.failed, 0);
}

#[test]
fn inactive_poison_leaves_minimal_clone_bounds_and_destroy_only_owners() {
    let exe = executable("policies.lani");
    let (output, trace) = traced(&exe, None);
    checked(&output, 0);
    let allocations = ledger(&trace, false);
    // Only the five DestroyOnly strings allocate. Poisoned inactive leaves
    // trap if called; CloneOnly intentionally supplies no Destroy bound.
    assert_eq!(allocations.attempts, [4; 5], "{trace}");
    assert_eq!(allocations.failed, 0);
}

#[test]
fn owned_typed_errors_roll_back_exactly_once_and_every_reached_oom_is_balanced() {
    let exe = executable("owned_errors.lani");
    let (output, trace) = traced(&exe, None);
    checked(&output, 0);
    let baseline = ledger(&trace, true);
    assert_eq!(baseline.failed, 0);
    // Three Option cases, six active Result arm/stage cases and nine Pair
    // first/second stage cases. Fourteen failures return independent owned E.
    assert_eq!(baseline.messages, 14, "{trace}");
    assert_eq!(baseline.attempts.len(), 45, "{trace}");
    assert_eq!(
        baseline.attempts.iter().filter(|&&size| size == 5).count(),
        14
    );
    assert!(baseline.attempts.iter().all(|&size| matches!(size, 4 | 5)));
    for index in 1..=baseline.attempts.len() {
        let (output, trace) = traced(&exe, Some(index));
        checked(&output, 4);
        let actual = ledger(&trace, true);
        assert_eq!(
            actual.attempts,
            baseline.attempts[..index],
            "OOM{index}: {trace}"
        );
        assert_eq!(actual.failed, 1, "OOM{index}: {trace}");
        assert_eq!(trace.matches("INJECTED").count(), 1, "OOM{index}: {trace}");
    }
    eprintln!("18 callback cases, 14 owned errors and all 45 reached allocation failures checked");
}

#[test]
fn absent_opt_in_wrong_scalar_error_and_missing_leaf_bounds_reject_at_callers() {
    for (name, call) in [
        (
            "no_opt_in.lani",
            "duplicate<core::option::Option<Marker>,Fault>",
        ),
        (
            "wrong_scalar_error.lani",
            "fixture::consumer::duplicate<i32,Wrong>",
        ),
        (
            "missing_pair_destroy.lani",
            "core::clone_values::try_clone_pair<Only,Only,Never,Never>",
        ),
        (
            "missing_option_clone.lani",
            "core::clone_values::try_clone_option<Only,Never>",
        ),
    ] {
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/stdlib_foundation/clone_values")
            .join(name);
        let source = fs::read_to_string(path).unwrap();
        let (line, text) = source
            .lines()
            .enumerate()
            .find(|(_, text)| text.trim().starts_with(call))
            .expect("rejected source call");
        let error = compile(name).expect_err("missing selected protocol must reject");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error:?}");
        let label = diagnostic.primary_label.expect("caller source label");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        assert_eq!(label.line, line + 1, "{name}: {label:?}");
        assert_eq!(
            label.source_line.as_deref().map(str::trim),
            Some(text.trim()),
            "{name}: {label:?}"
        );
    }
}
