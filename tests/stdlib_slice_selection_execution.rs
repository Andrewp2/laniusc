//! Checked nth-element selection: rank, partitions, permutation and aliasing.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/slice_selection")
        .join(name);
    let stdlib = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
}

fn execute(name: &str) {
    let bytes = compile(name).unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_slice_selection", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_slice_selection", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "checked slice selection native contracts",
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
    assert_eq!(
        events
            .lines()
            .filter(|line| line.starts_with("execve("))
            .count(),
        1,
        "{events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.starts_with("exit(") || line.starts_with("exit_group("))
            .count(),
        1,
        "{events}"
    );
    assert!(
        events.lines().all(|line| line.starts_with("execve(")
            || line.starts_with("exit(")
            || line.starts_with("exit_group(")),
        "pure selection must not allocate or call host services: {events}"
    );
}

#[test]
fn slice_selection_custom_and_natural_functions_return_live_nth_aliases() {
    execute("admission.lani");
}

#[test]
fn slice_selection_executes_rank_partition_permutation_bounds_and_stride_contracts() {
    execute("contracts.lani");
}

#[test]
fn slice_selection_requires_matching_comparator_and_natural_order_bounds() {
    for name in [
        "negative_missing_comparator.lani",
        "negative_wrong_comparator.lani",
        "negative_missing_ord.lani",
    ] {
        let error = compile(name).expect_err("selection requires its declared ordering capability");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic
            .primary_label
            .expect("explicit selection ordering requirement");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        let line = label.source_line.as_deref().unwrap_or("");
        assert!(
            line.contains("core::slice::select_nth_unstable")
                && line.contains("rejected_selection_bound"),
            "relevant selection bound: {label:?}"
        );
    }
}
