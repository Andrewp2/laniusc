//! Strong components: deterministic owners, exact condensation and early rejection.
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

fn execute(name: &str, allocating: bool) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended_graph_components")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_graph_components", name, None);
    executable.write_bytes(bytes); // Also applies the shared in-function jump checks.
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_graph_components", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "strong component native contracts",
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
            assert!(line.ends_with("= 0"), "{events}");
            continue;
        }
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            exits += 1;
            continue;
        }
        assert!(
            allocating,
            "component preflight must have no host effects: {events}"
        );
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let (arguments, result) = arguments.split_once(')').expect("mmap arguments");
            let length = arguments
                .split(',')
                .nth(1)
                .unwrap()
                .trim()
                .parse::<usize>()
                .unwrap();
            let address = result.trim().strip_prefix('=').unwrap().trim();
            assert!(
                address.starts_with("0x") && length > 0 && length <= 4096,
                "bounded successful reservation: {events}"
            );
            assert!(
                live.insert(address.to_owned(), length).is_none(),
                "live address reused: {events}"
            );
            acquisitions += 1;
            assert!(
                acquisitions <= 256 && live.len() <= 32,
                "bounded fixture storage: {events}"
            );
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let (address, length) = arguments.split_once(',').unwrap();
            assert_eq!(result.trim(), "= 0", "{events}");
            assert_eq!(
                live.remove(address.trim()),
                Some(length.trim().parse::<usize>().unwrap()),
                "exact address and extent release: {events}"
            );
        } else {
            panic!("unexpected component host effect: {events}");
        }
    }
    assert_eq!(entries, 1, "{events}");
    assert_eq!(exits, 1, "{events}");
    assert!(
        live.is_empty(),
        "all graph/result/workspace owners released: {events}"
    );
    if allocating {
        assert!(acquisitions > 0, "real owner execution: {events}");
    }
}

#[test]
fn strong_components_and_condensation_execute_canonical_native_admission() {
    execute("admission.lani", true);
}
#[test]
fn strong_component_owners_exact_edges_closed_queries_and_work_boundaries_execute() {
    execute("contracts.lani", true);
}
#[test]
fn strong_component_preflight_preserves_validation_precedence_without_host_effects() {
    execute("preflight.lani", false);
}
