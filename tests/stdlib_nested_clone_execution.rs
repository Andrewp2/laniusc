#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
// Accepted native Linux x86-64 via GPU compiler checkpoint 59612b34.
// Seven groups: 10 compilation jobs, 6 ELFs, 4 rejections and 16 native runs.
// Sources use the production stdlib and durable user root; see the owned guide.
mod common;

use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Output},
    time::Duration,
};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixture_root = root.join("tests/fixtures/stdlib_foundation/nested_clone");
    let entry = fixture_root.join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixture_root],
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
}

fn executable(name: &str) -> common::TempArtifact {
    let bytes = compile(name).unwrap_or_else(|error| {
        panic!("{name}: initial nested ownership admission failed: {error}")
    });
    assert!(
        common::x86_jumps::is_x86_64_executable(&bytes),
        "{name}: positive compile did not return a native ELF"
    );
    let exe = common::TempArtifact::new("nested_clone_admission", name, None);
    // TempArtifact::write_bytes runs the unchanged strict common x86 transfer
    // checker before writing bytes. No local exception or alternate checker.
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn execute(name: &str) {
    let exe = executable(name);
    let output = common::short_process_output_with_timeout(
        format!("nested memory ownership frontier: {name}"),
        &mut Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{name}: {output:?}"
    );
    eprintln!("accepted {name}: strict native ELF, exit0, empty stdout/stderr");
}

struct MappingLedger {
    attempts: Vec<usize>,
    failed: usize,
    messages: usize,
}

fn traced(exe: &common::TempArtifact, fail_at: Option<usize>) -> (Output, String) {
    let trace = common::TempArtifact::new("nested_clone_admission", "mapping_trace", None);
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
        "bounded nested clone mapping trace",
        &mut command,
        Duration::from_secs(5),
    );
    let text = std::fs::read_to_string(trace.path()).unwrap();
    (output, text)
}

fn ledger(trace: &str, owned_messages: bool) -> MappingLedger {
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
            let (address, tail) = tail.split_once(',').unwrap();
            let size: usize = tail.split_once(')').unwrap().0.trim().parse().unwrap();
            assert_eq!(live.remove(address), Some(size), "{trace}");
            assert!(line.ends_with(" = 0"), "{trace}");
            if owned_messages && size == 5 {
                messages += 1;
                // The leaf error owner is last: all failed destination and
                // source owners have gone before the caller releases E.
                assert!(
                    live.is_empty(),
                    "E was released before other owners: {trace}"
                );
            }
        }
    }
    assert!(live.is_empty(), "unreleased mapping owners: {trace}");
    MappingLedger {
        attempts,
        failed,
        messages,
    }
}

fn assert_native(output: &Output, expected: i32) {
    assert_eq!(output.status.code(), Some(expected), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn full_contracts_cover_three_levels_aliases_pop_reset_and_zero_sized_empty_paths() {
    let contracts = executable("nested_contracts.lani");
    let (output, trace) = traced(&contracts, None);
    assert_native(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    let allocations = ledger(&trace, false);
    assert_eq!(allocations.failed, 0, "{trace}");
    assert!(
        !allocations.attempts.is_empty(),
        "nested String ownership must exercise storage"
    );
    let empty = executable("empty_zero_sized.lani");
    let (output, trace) = traced(&empty, None);
    assert_native(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    assert!(
        ledger(&trace, false).attempts.is_empty(),
        "empty/ZST paths allocated: {trace}"
    );
}

#[test]
fn ten_reached_allocation_failures_preserve_borrowed_sources_and_release_all_destinations() {
    let exe = executable("allocation_paths.lani");
    let (output, trace) = traced(&exe, None);
    assert_native(&output, 0);
    let widths = std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .map(|line| line.parse::<usize>().unwrap())
        .collect::<Vec<_>>();
    assert_eq!(
        widths.len(),
        3,
        "runtime fixture reports two layouts plus the semantic error path"
    );
    assert!(
        widths[..2]
            .iter()
            .all(|&value| value > 0 && value <= i32::MAX as usize / 2)
    );
    assert_eq!(widths[2], 0, "baseline must report success");
    let string = 2 * widths[0];
    let vector = 2 * widths[1];
    // Source allocations (3), then outer reserve, row0 reserve/leaves and
    // row1 reserve/leaves (7). Values come from runtime size_of, not a guessed
    // native record representation; the actual syscall arguments must agree.
    let expected = vec![4, string, vector, vector, string, 4, 4, string, 4, 4];
    let baseline = ledger(&trace, false);
    assert_eq!(baseline.attempts, expected, "{trace}");
    assert_eq!(baseline.failed, 0, "{trace}");
    assert!(!trace.contains("INJECTED"), "{trace}");
    for index in 1..=expected.len() {
        let (failed, trace) = traced(&exe, Some(index));
        assert_native(&failed, 4);
        let reported = std::str::from_utf8(&failed.stdout)
            .unwrap()
            .lines()
            .map(|line| line.parse::<usize>().unwrap())
            .collect::<Vec<_>>();
        assert_eq!(reported.len(), 3, "OOM{index}: {failed:?}");
        assert_eq!(
            reported[..2],
            widths[..2],
            "fixture layout identity changed at OOM{index}"
        );
        // Independent ordinal oracle: setup1/2/3, outer Storage, row0/1
        // Storage, or exact row+column leaf AllocationFailed.
        let tags = [1, 2, 3, 10, 20, 100, 101, 21, 102, 103];
        assert_eq!(
            reported[2],
            tags[index - 1],
            "wrong typed error nesting/index at OOM{index}"
        );
        let actual = ledger(&trace, false);
        assert_eq!(actual.attempts, expected[..index], "OOM{index}: {trace}");
        assert_eq!(actual.failed, 1, "OOM{index}: {trace}");
        assert_eq!(trace.matches("INJECTED").count(), 1, "OOM{index}: {trace}");
    }
    eprintln!("allocation_paths: baseline 10 exact requests; all 10 reached OOM positions checked");
}

#[test]
fn owned_error_matrix_retains_each_index_stage_and_separate_error_owner() {
    let exe = executable("owned_error_matrix.lani");
    let (output, trace) = traced(&exe, None);
    assert_native(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    let actual = ledger(&trace, true);
    assert_eq!(actual.failed, 0, "{trace}");
    assert_eq!(
        actual.messages, 8,
        "every 2x2 index/before-after stage must transfer and release E: {trace}"
    );
    assert_eq!(
        actual.attempts.iter().filter(|&&size| size == 5).count(),
        8,
        "{trace}"
    );
    eprintln!(
        "owned_error_matrix: 8 index/stage cases; E released after destination+source owners"
    );
}

fn reject_at(name: &str, code: &str, line: usize, call: &str) {
    let source = std::fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/stdlib_foundation/nested_clone")
            .join(name),
    )
    .unwrap();
    let expected = source.lines().nth(line - 1).unwrap().trim();
    assert!(
        expected.contains(call),
        "negative fixture source location drifted: {name}"
    );
    let error =
        compile(name).expect_err("contradictory or missing selected prerequisites must reject");
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, code, "{name}: {error:?}");
    let label = diagnostic
        .primary_label
        .expect("the actual consumer must retain its source location");
    assert!(label.path.ends_with(name), "{name}: {label:?}");
    assert_eq!(label.line, line, "{name}: {label:?}");
    assert_eq!(
        label.source_line.as_deref().map(str::trim),
        Some(expected),
        "{name}: {label:?}"
    );
    eprintln!(
        "rejected {name}: {code} at {}:{}",
        label.path.display(),
        label.line
    );
}

#[test]
fn contradictory_error_and_each_missing_leaf_prerequisite_reject_at_the_source_call() {
    reject_at(
        "contradictory_error.lani",
        "LNC0006",
        11,
        "alloc::clone_vec::try_clone<T,E>",
    );
    reject_at(
        "missing_destroy.lani",
        "LNC0008",
        11,
        "fixture::prerequisites::CloneOnly",
    );
    reject_at(
        "missing_clone.lani",
        "LNC0008",
        11,
        "fixture::prerequisites::ReleaseOnly",
    );
}

#[test]
fn nested_strings_clone_independently_and_release_after_borrowed_source_owners() {
    let exe = executable("nested_strings.lani");
    let (output, trace) = traced(&exe, None);
    assert_native(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    let actual = ledger(&trace, false);
    assert_eq!(actual.failed, 0, "{trace}");
    assert!(!actual.attempts.is_empty(), "{trace}");
}

#[test]
fn nested_owned_leaf_error_survives_destination_and_source_release() {
    execute("owned_error.lani");
}

#[test]
fn missing_opt_in_rejects_the_exact_nested_vector_protocol_application() {
    const NAME: &str = "no_opt_in.lani";
    const CALL: &str = "alloc::clone::from_view<alloc::vec::Vec<alloc::string::String>,alloc::clone::Error<alloc::string::Error>>(core::slice::view(rows,0).unwrap());";
    // Here T=Vec<String>, E=alloc::clone::Error<String::Error>. from_view
    // requires both TryClone<T,E> and Destroy<T>. Neither Vec implementation
    // is imported. Expected rejection is the actual caller bound, despite
    // zero runtime entries, rather than a parse/layout/native-definition error.
    let source = std::fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/stdlib_foundation/nested_clone")
            .join(NAME),
    )
    .unwrap();
    assert_eq!(source.lines().nth(13).map(str::trim), Some(CALL));
    let error = compile(NAME).expect_err("missing Vec protocol impls cannot produce an ELF");
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0008", "{NAME}: {error:?}");
    let label = diagnostic
        .primary_label
        .expect("missing protocol application must retain its actual caller location");
    assert!(label.path.ends_with(NAME), "{NAME}: {label:?}");
    assert_eq!(label.line, 14, "{NAME}: {label:?}");
    assert_eq!(
        label.source_line.as_deref().map(str::trim),
        Some(CALL),
        "{NAME}: {label:?}"
    );
    eprintln!(
        "rejected {NAME}: {} at {}:{}; expected missing TryClone<Vec<String>,Error<StringError>> / Destroy<Vec<String>>",
        diagnostic.code,
        label.path.display(),
        label.line,
    );
}
