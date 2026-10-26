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
    let fixture_root = root.join("tests/fixtures/stdlib_foundation/clone_tree_set");
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
    let exe = common::TempArtifact::new("clone_tree_set", name, None);
    // Preserve the common strict ELF and instruction-transfer checker.
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn traced(exe: &common::TempArtifact, fail_at: Option<usize>) -> (Output, String) {
    let trace = common::TempArtifact::new("clone_tree_set", "mapping_trace", None);
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
        "bounded ordered-set ownership trace",
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
fn strings_generic_selection_holes_transfer_reset_empty_and_zero_sized_keys() {
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
fn all_reached_allocations_preserve_source_and_report_sorted_element_errors() {
    let exe = executable("allocation_paths.lani");
    let (output, trace) = traced(&exe, None);
    status(&output, 0);
    assert_eq!(numbers(&output), vec![0]);
    let baseline = ledger(&trace, false);
    assert_eq!(baseline.failed, 0);
    assert_eq!(baseline.attempts.len(), 9, "{trace}");
    let source_nodes = baseline.attempts[4];
    assert!(source_nodes > 0 && source_nodes % 6 == 0);
    // Four original Strings, six-node source backing, then exactly one
    // three-node final reservation before the three cloned String leaves.
    let expected = vec![4, 4, 4, 4, source_nodes, source_nodes / 2, 4, 4, 4];
    assert_eq!(baseline.attempts, expected, "{trace}");
    let tags = [1, 2, 3, 4, 5, 10, 20, 21, 22];
    for index in 1..=expected.len() {
        let (output, trace) = traced(&exe, Some(index));
        status(&output, 4);
        assert_eq!(
            numbers(&output),
            vec![tags[index - 1]],
            "OOM{index}: {output:?}"
        );
        let actual = ledger(&trace, false);
        assert_eq!(actual.attempts, expected[..index], "OOM{index}: {trace}");
        assert_eq!(actual.failed, 1, "OOM{index}: {trace}");
        assert_eq!(trace.matches("INJECTED").count(), 1, "OOM{index}: {trace}");
    }
}

#[test]
fn owned_errors_and_eq_or_order_changes_release_only_destination_owners() {
    let exe = executable("owned_errors.lani");
    let (output, trace) = traced(&exe, None);
    status(&output, 0);
    assert!(output.stdout.is_empty());
    let actual = ledger(&trace, true);
    assert_eq!(actual.failed, 0);
    assert_eq!(
        actual.messages, 6,
        "three sorted indices x two partial failure stages: {trace}"
    );
    assert_eq!(
        actual.attempts.iter().filter(|&&size| size == 5).count(),
        6,
        "{trace}"
    );
}

#[test]
fn bounded_ordered_model_and_reserved_construction_cost_are_observable() {
    let exe = executable("cost.lani");
    let (output, trace) = traced(&exe, None);
    status(&output, 0);
    let reported = numbers(&output);
    assert_eq!(reported.len(), 10);
    for row in reported.chunks_exact(5) {
        let n = row[0];
        assert!([64, 512].contains(&n));
        assert!(
            row[1] > 3 * n,
            "nontrivial checked insertion comparisons: {row:?}"
        );
        let height = (usize::BITS - n.leading_zeros()) as usize;
        assert!(
            row[1] < 32 * n * height,
            "bounded AVL insertion work: {row:?}"
        );
        assert_eq!(
            row[2..],
            [n, n, n],
            "exact equality/clone/release count: {row:?}"
        );
    }
    let actual = ledger(&trace, false);
    assert_eq!(actual.failed, 0);
    assert_eq!(
        actual.attempts.len(),
        4,
        "one source and one final reserve per size: {trace}"
    );
    let node_bytes = actual.attempts[0] / 64;
    assert!(node_bytes > 0);
    assert_eq!(
        actual.attempts,
        vec![
            64 * node_bytes,
            64 * node_bytes,
            512 * node_bytes,
            512 * node_bytes
        ]
    );

    let exe = executable("model.lani");
    let output = common::short_process_output_with_timeout(
        "512-state ordered deep-clone model",
        &mut Command::new(exe.path()),
    );
    status(&output, 0);
    let mut model = BTreeMap::<i32, i32>::new();
    let mut state = 113;
    let mut expected = Vec::new();
    let mut clone_states = 0;
    for step in 0..512 {
        state = (state * 73 + 41) % 997;
        let (key, op) = if step < 64 {
            (step, 0)
        } else {
            (state % 64, step % 7)
        };
        let stamp = 100 + step;
        if step == 255 {
            model.clear();
        } else if step != 383 {
            match op {
                0 => {
                    model.entry(key).or_insert(stamp);
                }
                1 => {
                    model.insert(key, stamp);
                }
                2 => {
                    model.remove(&key);
                }
                3 => {}
                5 if step % 2 == 0 => {
                    model.pop_first();
                }
                5 => {
                    model.pop_last();
                }
                _ => {
                    clone_states += 1;
                }
            }
        }
        expected.push(model.len());
        expected.push(
            model
                .iter()
                .map(|(&key, &stamp)| (step as usize + 1) * (key as usize + 1) * stamp as usize)
                .sum(),
        );
    }
    assert!(clone_states > 100);
    assert_eq!(
        numbers(&output),
        expected,
        "all 512 ordered content/representative snapshots"
    );
}

#[test]
fn missing_opt_in_and_contradictory_selected_error_reject_at_actual_calls() {
    for (name, call, code) in [
        (
            "no_opt_in.lani",
            "release<alloc::tree_set::TreeSet",
            "LNC0008",
        ),
        (
            "contradictory_error.lani",
            "alloc::clone_tree_set::try_clone<",
            "LNC0006",
        ),
    ] {
        let source = std::fs::read_to_string(
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("tests/fixtures/stdlib_foundation/clone_tree_set")
                .join(name),
        )
        .unwrap();
        let (line, text) = source
            .lines()
            .enumerate()
            .find(|(_, text)| text.trim().starts_with(call))
            .unwrap();
        let error = compile(name)
            .expect_err("selected clone/release contracts must match even on empty sets");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, code, "{name}: {error:?}");
        let label = diagnostic
            .primary_label
            .expect("actual consumer source label");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        assert_eq!(label.line, line + 1, "{name}: {label:?}");
        assert_eq!(
            label.source_line.as_deref().map(str::trim),
            Some(text.trim()),
            "{name}: {label:?}"
        );
    }
}
