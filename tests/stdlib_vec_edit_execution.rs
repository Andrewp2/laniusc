//! Owned vector editing: stable survivors, exact cleanup effects, and trait bounds.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/stdlib_vec_edit").join(name)
}
fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let entry = fixture(name);
    let stdlib = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
}
fn executable(name: &str) -> common::TempArtifact {
    let bytes = compile(name).unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_vec_edit", name, None);
    executable.write_bytes(bytes); // Shared in-function jump validation.
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn execute(name: &str, expected_allocations: usize) {
    let executable = executable(name);
    let trace = common::TempArtifact::new("laniusc_vec_edit", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "owned vector editing contracts",
        Command::new("strace").args(["-qq", "-o"]).arg(trace.path())
            .args(["-e", "trace=all", "-e", "signal=none"]).arg(executable.path()),
        Duration::from_secs(15),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    common::assert_command_success(name, &output);
    assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{output:?}\n{events}");
    let mut live = std::collections::BTreeMap::<u64,u64>::new();
    let mut allocations = 0;
    let mut launches = 0;
    let mut exits = 0;
    for line in events.lines() {
        if line.starts_with("execve(") && line.ends_with("= 0") { launches += 1; }
        else if let Some(arguments) = line.strip_prefix("mmap(") {
            let length: u64 = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let result = line.rsplit(" = ").next().unwrap().split_whitespace().next().unwrap();
            let address = u64::from_str_radix(result.strip_prefix("0x").expect("successful allocation"), 16).unwrap();
            assert!(length > 0 && live.insert(address,length).is_none(), "{events}");
            allocations += 1;
        }
        else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (address, rest) = arguments.split_once(',').unwrap();
            let address = u64::from_str_radix(address.trim().strip_prefix("0x").unwrap(),16).unwrap();
            let length: u64 = rest.split(')').next().unwrap().trim().parse().unwrap();
            assert!(line.ends_with(" = 0"), "{events}");
            assert_eq!(live.remove(&address), Some(length), "{events}");
        }
        else if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") { exits += 1; }
        else { panic!("unexpected vector editing host effect: {events}"); }
    }
    assert!(live.is_empty(), "{events}");
    assert_eq!((allocations,launches,exits), (expected_allocations,1,1), "{events}");
}
#[test]
fn vec_edit_all_methods_execute_tiny_composite_admission() { execute("admission.lani", 2); }
#[test]
fn vec_edit_stable_survivors_exact_callback_cleanup_and_bounds_execute() { execute("contracts.lani", 3); }
#[test]
fn vec_edit_generic_compound_layouts_and_float_partial_equality_execute() { execute("types.lani", 4); }
fn reject_bounds(names: &[&str]) {
    for name in names {
        let error = compile(name).expect_err("owned vector editing requires its declared capabilities");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic.primary_label.expect("source-local capability rejection");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        assert!(label.source_line.as_deref().unwrap_or("").contains("rejected_edit_bound"), "{name}: {label:?}");
    }
}
#[test]
fn vec_edit_all_methods_require_destroy_and_natural_dedup_requires_partial_eq() {
    reject_bounds(&["negative_retain_destroy.lani", "negative_dedup_by_destroy.lani",
        "negative_dedup_destroy.lani", "negative_truncate_destroy.lani", "negative_clear_destroy.lani",
        "negative_partial_eq.lani"]);
}
#[test]
fn vec_edit_predicates_require_exact_mapper_input_and_bool_result() {
    reject_bounds(&["negative_retain_mapper_missing.lani", "negative_retain_mapper_input.lani",
        "negative_retain_mapper_result.lani", "negative_dedup_by_mapper_missing.lani",
        "negative_dedup_by_mapper_input.lani", "negative_dedup_by_mapper_result.lani"]);
}
