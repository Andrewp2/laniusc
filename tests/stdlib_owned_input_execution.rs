//! Bounded owned whole-input collection, actual reader progress and cleanup.
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
        .join("tests/fixtures/stdlib_foundation/owned_input")
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
    let executable = common::TempArtifact::new("laniusc_owned_input", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_owned_input", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "bounded owned input native contracts",
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
                address.starts_with("0x") && length > 0,
                "successful owner acquisition: {events}"
            );
            assert!(
                live.insert(address.to_string(), length).is_none(),
                "live address reused: {events}"
            );
            acquisitions += 1;
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let (address, length) = arguments.split_once(',').unwrap();
            let length = length.trim().parse::<usize>().unwrap();
            assert_eq!(
                result.trim().strip_prefix('=').unwrap().trim(),
                "0",
                "{events}"
            );
            assert_eq!(
                live.remove(address.trim()),
                Some(length),
                "matched owner address and size: {events}"
            );
        } else {
            panic!("unexpected host effect in scripted collection: {events}");
        }
    }
    assert_eq!(entries, 1, "{events}");
    assert_eq!(exits, 1, "{events}");
    assert!(
        acquisitions > 0 && live.is_empty(),
        "all reached owners released exactly once: {events}"
    );
}

#[test]
fn owned_input_generic_bytes_and_split_utf8_execute_admission() {
    execute("admission.lani");
}

#[test]
fn owned_input_executes_scripted_caps_probes_quotas_failures_and_utf8_precedence() {
    execute("contracts.lani");
}
