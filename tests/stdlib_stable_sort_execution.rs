//! Stable whole-value permutations and fallible workspace admission.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::Duration,
};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/stable_sort")
        .join(name);
    let stdlib = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
}
fn execute(name: &str, expected_allocations: Option<usize>) {
    let bytes = compile(name).unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_stable_sort", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_stable_sort", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "stable sort native contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=all", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(10),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    common::assert_command_success(name, &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}\n{events}"
    );
    let mut live = BTreeMap::new();
    let mut acquisitions = 0;
    let mut entries = 0;
    let mut exits = 0;
    for line in events.lines() {
        if line.starts_with("execve(") {
            entries += 1;
            continue;
        }
        if line.starts_with("exit(") || line.starts_with("exit_group(") {
            exits += 1;
            continue;
        }
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let length = arguments
                .split(',')
                .nth(1)
                .unwrap()
                .trim()
                .parse::<usize>()
                .unwrap();
            let address = result.trim().strip_prefix('=').unwrap().trim();
            assert!(
                address.starts_with("0x") && length > 0,
                "successful workspace reservation: {events}"
            );
            assert!(
                live.insert(address.to_owned(), length).is_none(),
                "live address reused: {events}"
            );
            assert_eq!(
                live.len(),
                1,
                "at most one private workspace at a time: {events}"
            );
            acquisitions += 1;
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let (address, length) = arguments.split_once(',').unwrap();
            assert_eq!(result.trim(), "= 0", "{events}");
            assert_eq!(
                live.remove(address.trim()),
                Some(length.trim().parse::<usize>().unwrap()),
                "exact address and size release: {events}"
            );
        } else {
            panic!("unexpected host effect in stable sort: {events}");
        }
    }
    assert_eq!(entries, 1, "{events}");
    assert_eq!(exits, 1, "{events}");
    assert!(
        live.is_empty(),
        "all temporary workspaces released: {events}"
    );
    if let Some(expected) = expected_allocations {
        assert_eq!(acquisitions, expected, "{events}");
    } else {
        assert!(
            acquisitions > 0,
            "actual stable workspace execution: {events}"
        );
    }
}
#[test]
fn stable_sort_natural_and_custom_record_orders_execute_stable_admission() {
    execute("admission.lani", Some(2));
}

#[test]
fn stable_sort_preserves_compound_ties_successive_policies_and_real_layouts() {
    execute("contracts.lani", None);
}

#[test]
fn stable_sort_metadata_capacity_trivial_and_zero_sized_admission_uses_no_host_memory() {
    execute("bounds.lani", Some(0));
}

#[test]
fn stable_sort_requires_exact_comparator_operands_or_natural_ord() {
    for name in [
        "negative_missing_comparator.lani",
        "negative_wrong_left.lani",
        "negative_wrong_right.lani",
        "negative_missing_ord.lani",
    ] {
        let error =
            compile(name).expect_err("stable sort requires its declared comparison capability");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic
            .primary_label
            .expect("explicit stable sorting capability");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        let line = label.source_line.as_deref().unwrap_or("");
        assert!(
            line.contains("alloc::slice::sort") && line.contains("rejected_stable_bound"),
            "relevant stable sort bound: {label:?}"
        );
    }
}
