//! Scoped map updates: generic admission, exact effects, and capability bounds.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/stdlib_map_update").join(name)
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
    let executable = common::TempArtifact::new("laniusc_map_update", name, None);
    executable.write_bytes(bytes); // Shared in-function jump validation.
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn execute(name: &str, expected_allocations: usize) {
    let executable = executable(name);
    let trace = common::TempArtifact::new("laniusc_map_update", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "scoped map update contracts",
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
        else { panic!("unexpected map update host effect: {events}"); }
    }
    assert!(live.is_empty(), "{events}");
    assert_eq!((allocations,launches,exits), (expected_allocations,1,1), "{events}");
}
#[test]
fn map_updates_generic_compound_values_and_results_execute_tiny_admission() { execute("admission.lani", 2); }
#[test]
fn map_updates_preserve_representatives_structure_and_exact_callback_lookup_effects() { execute("contracts.lani", 2); }
#[test]
fn map_updates_bool_array_and_zero_sized_shapes_execute() { execute("shapes.lani", 10); }
#[test]
fn map_updates_require_mapper_and_map_key_capabilities() {
    for name in ["negative_hash_mapper.lani", "negative_tree_mapper.lani", "negative_hash_key_hash.lani", "negative_hash_key_eq.lani", "negative_tree_key_ord.lani"] {
        let error = compile(name).expect_err("update requires its declared Mapper and map key capabilities");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic.primary_label.expect("source-local capability rejection");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        assert!(label.source_line.as_deref().unwrap_or("").contains("rejected_update_bound"), "{name}: {label:?}");
    }
}
