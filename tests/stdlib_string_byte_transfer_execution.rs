//! Validated zero-copy String/Vec transfers retain one explicit cleanup owner.
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

fn result(line: &str) -> &str {
    line.rsplit_once('=').unwrap().1.trim()
}

fn check_trace(events: &str) {
    let mut live = BTreeMap::<String, usize>::new();
    let (mut acquired, mut released, mut phases, mut entries, mut exits) = (0, 0, 0, 0, 0);
    let (mut pure, mut done) = (false, false);
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert_eq!(result(line), "1", "{events}");
            if line.contains("\"P\", 1)") {
                assert!(!pure && !done, "{events}");
                pure = true;
            } else if line.contains("\"p\", 1)") {
                assert!(pure && !done, "{events}");
                pure = false;
                phases += 1;
            } else {
                assert!(
                    line.contains("\"D\", 1)") && !pure && !done && live.is_empty(),
                    "{events}"
                );
                done = true;
            }
            continue;
        }
        assert!(
            !pure,
            "validation/ownership transfer reached a host call: {line}\n{events}"
        );
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done, "cleanup checkpoint precedes exit: {events}");
            exits += 1;
            continue;
        }
        assert!(!done, "only exit follows completed cleanup: {events}");
        if line.starts_with("execve(") {
            assert_eq!(result(line), "0", "{events}");
            entries += 1;
        } else if let Some(arguments) = line.strip_prefix("mmap(") {
            let length: usize = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let address = result(line).split_whitespace().next().unwrap();
            assert!(
                address.starts_with("0x"),
                "actual successful allocation: {events}"
            );
            assert!(
                live.insert(address.to_owned(), length).is_none(),
                "duplicate live owner: {events}"
            );
            acquired += 1;
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let arguments = arguments.split_once(')').unwrap().0;
            let (address, length) = arguments.split_once(',').unwrap();
            let length: usize = length.trim().parse().unwrap();
            assert_eq!(
                live.remove(address.trim()),
                Some(length),
                "matching owner and extent: {events}"
            );
            assert_eq!(result(line), "0", "{events}");
            released += 1;
        } else {
            panic!("unexpected transfer host call: {line}\n{events}");
        }
    }
    assert!(done && !pure && live.is_empty(), "{events}");
    // 8 valid inputs (7 initially allocated), 16 independent source reuses,
    // 12 invalid inputs and 2 truncated initialized prefixes.
    assert_eq!(
        (acquired, released, phases, entries, exits),
        (37, 37, 42, 1, 1),
        "{events}"
    );
}

#[test]
fn string_byte_transfers_validate_preserve_identity_and_release_once() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/string_byte_transfer/contracts.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("String byte ownership transfer", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("String byte ownership transfer: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_string_transfer", "contracts", None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_string_transfer", "owners", None);
    let output = common::process_output_with_timeout(
        "String byte ownership transfer contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=execve,write,mmap,mremap,munmap,brk,exit,exit_group",
                "-e",
                "signal=none",
            ])
            .arg(executable.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty(), "{output:?}");
    let mut checkpoints = b"Pp".repeat(42);
    checkpoints.push(b'D');
    assert_eq!(output.stderr, checkpoints, "{output:?}");
    check_trace(&fs::read_to_string(trace.path()).unwrap());
}
