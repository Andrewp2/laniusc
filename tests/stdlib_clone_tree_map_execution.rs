#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
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
    let fixture_root = root.join("tests/fixtures/stdlib_foundation/clone_tree_map");
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
    let bytes = compile(name).unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes), "{name}");
    let exe = common::TempArtifact::new("clone_tree_map", name, None);
    // Preserve the common strict ELF and instruction-transfer checker.
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn traced(exe: &common::TempArtifact, fail_at: Option<usize>) -> (Output, String) {
    let trace = common::TempArtifact::new("clone_tree_map", "mapping_trace", None);
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
        "bounded ordered-map ownership trace",
        &mut command,
        Duration::from_secs(5),
    );
    (output, std::fs::read_to_string(trace.path()).unwrap())
}

struct Ledger {
    attempts: Vec<usize>,
    failed: usize,
    messages: usize,
}

fn ledger(trace: &str, owned_errors: bool) -> Ledger {
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
            if owned_errors && size == 5 {
                messages += 1;
                assert!(
                    live.is_empty(),
                    "owned E released before other owners: {trace}"
                );
            }
        }
    }
    assert!(live.is_empty(), "leaked owners: {trace}");
    Ledger {
        attempts,
        failed,
        messages,
    }
}

fn status(output: &Output, expected: i32) {
    assert_eq!(output.status.code(), Some(expected), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

fn numbers(output: &Output) -> Vec<usize> {
    std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .map(|line| line.parse::<usize>().unwrap())
        .collect()
}

#[test]
fn strings_nested_values_holes_transfer_reset_empty_and_zero_sized_keys() {
    for name in [
        "contracts.lani",
        "empty.lani",
        "zero_sized.lani",
        "destroy_only.lani",
    ] {
        let exe = executable(name);
        let (output, trace) = traced(&exe, None);
        status(&output, 0);
        assert!(output.stdout.is_empty(), "{name}: {output:?}");
        let actual = ledger(&trace, false);
        assert_eq!(actual.failed, 0, "{trace}");
        if name == "empty.lani" {
            assert!(actual.attempts.is_empty(), "{trace}");
        } else {
            assert!(!actual.attempts.is_empty(), "{name}: {trace}");
        }
    }
}

#[test]
fn canonical_sorted_initialization_preserves_rejections_and_uses_reserved_storage() {
    let exe = executable("init_sorted.lani");
    let (output, trace) = traced(&exe, None);
    status(&output, 0);
    assert!(output.stdout.is_empty());
    let actual = ledger(&trace, false);
    assert_eq!(actual.failed, 0);
    assert_eq!(
        actual.attempts.len(),
        1,
        "24 sorted initializations must share one reservation: {trace}"
    );
    let exe = executable("init_sorted_allocation.lani");
    for fail in [None, Some(1)] {
        let (output, trace) = traced(&exe, fail);
        status(&output, if fail.is_some() { 4 } else { 0 });
        assert!(output.stdout.is_empty());
        let actual = ledger(&trace, false);
        assert_eq!(actual.attempts.len(), 1, "{trace}");
        assert_eq!(actual.failed, usize::from(fail.is_some()), "{trace}");
    }
}

#[test]
fn every_reached_allocation_failure_has_exact_sorted_key_value_error_and_no_leak() {
    let exe = executable("allocation_paths.lani");
    let (output, trace) = traced(&exe, None);
    status(&output, 0);
    let widths = numbers(&output);
    assert_eq!(widths.len(), 3);
    assert!(
        widths[..2]
            .iter()
            .all(|&size| size > 0 && size <= i32::MAX as usize / 4)
    );
    assert_eq!(widths[2], 0);
    let baseline = ledger(&trace, false);
    assert_eq!(baseline.failed, 0);
    assert_eq!(baseline.attempts.len(), 15, "{trace}");
    // Derive the private node width from the actual four-node source reserve;
    // Entry and String widths are reported by native size_of, not guessed.
    let source_nodes = baseline.attempts[4];
    assert!(source_nodes > 0 && source_nodes % 4 == 0);
    let expected = vec![
        4,
        4, // initial String construction uses its minimum growth capacity
        4,
        2 * widths[1],
        source_nodes,
        source_nodes / 2,
        2 * widths[0], // final nodes and staging before leaves
        2,
        2 * widths[1],
        4,
        4,
        2,
        2 * widths[1],
        4,
        4,
    ];
    assert_eq!(baseline.attempts, expected, "{trace}");
    let tags = [1, 2, 3, 4, 5, 10, 11, 20, 30, 100, 101, 21, 31, 102, 103];
    for index in 1..=expected.len() {
        let (output, trace) = traced(&exe, Some(index));
        status(&output, 4);
        let reported = numbers(&output);
        assert_eq!(reported.len(), 3, "OOM{index}: {output:?}");
        assert_eq!(reported[..2], widths[..2], "OOM{index}: {output:?}");
        assert_eq!(reported[2], tags[index - 1], "OOM{index}: {output:?}");
        let actual = ledger(&trace, false);
        assert_eq!(actual.attempts, expected[..index], "OOM{index}: {trace}");
        assert_eq!(actual.failed, 1, "OOM{index}: {trace}");
        assert_eq!(trace.matches("INJECTED").count(), 1, "OOM{index}: {trace}");
    }
}

#[test]
fn owned_key_value_errors_and_changed_keys_cleanup_before_error_owner_release() {
    let exe = executable("owned_errors.lani");
    let (output, trace) = traced(&exe, None);
    status(&output, 0);
    assert!(output.stdout.is_empty());
    let actual = ledger(&trace, true);
    assert_eq!(actual.failed, 0);
    assert_eq!(
        actual.messages, 12,
        "3 sorted indices x key/value x 2 failure stages: {trace}"
    );
    assert_eq!(
        actual.attempts.iter().filter(|&&size| size == 5).count(),
        12,
        "{trace}"
    );
}

#[test]
fn absent_opt_in_and_missing_leaf_protocols_reject_at_the_actual_consumer() {
    for (name, call) in [
        ("no_opt_in.lani", "release<alloc::tree_map::TreeMap"),
        ("missing_clone.lani", "alloc::clone_tree_map::try_clone<"),
        ("missing_destroy.lani", "alloc::clone_tree_map::try_clone<"),
    ] {
        let source = std::fs::read_to_string(
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("tests/fixtures/stdlib_foundation/clone_tree_map")
                .join(name),
        )
        .unwrap();
        let (line, text) = source
            .lines()
            .enumerate()
            .find(|(_, text)| text.trim().starts_with(call))
            .unwrap();
        let error =
            compile(name).expect_err("missing selected protocol must reject even for an empty map");
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
