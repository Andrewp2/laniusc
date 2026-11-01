//! Vector transfer: typed entry conservation, owner state and failure contracts.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/stdlib_vec_transfer").join(name)
}
fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let entry = fixture(name);
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")), user_roots: vec![],
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
}
fn executable(name: &str) -> common::TempArtifact {
    let bytes = compile(name).unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_vec_transfer", name, None);
    executable.write_bytes(bytes); // Shared in-function jump validation.
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn execute(name: &str, minimum_allocations: usize, maximum_allocations: usize) {
    let executable = executable(name);
    let trace = common::TempArtifact::new("laniusc_vec_transfer", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "vector transfer direct contracts",
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
        else { panic!("unexpected vector transfer host effect: {events}"); }
    }
    assert!(live.is_empty(), "{events}");
    assert!(allocations >= minimum_allocations && allocations <= maximum_allocations, "{events}");
    assert_eq!((launches,exits), (1,1), "{events}");
}
#[test]
fn vec_transfer_all_methods_execute_tiny_composite_admission() { execute("admission.lani", 4, 4); }
#[test]
fn vec_transfer_ranges_capacity_empty_noops_and_bounds_execute() { execute("contracts.lani", 31, 31); }
#[test]
fn vec_transfer_typed_layouts_and_nested_owners_execute() { execute("types.lani", 26, 26); }
#[test]
fn vec_transfer_zero_sized_maximum_counts_and_overflow_execute_without_allocation() { execute("zero_sized.lani", 0, 0); }
