//! Caller-backed buffering: borrowed state, handoff, errors, and capabilities.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;
use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_caller_buffered/direct")
        .join(name)
}
fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let entry = fixture(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib")),
        user_roots: vec![fixture("")],
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
}
fn executable(name: &str) -> common::TempArtifact {
    let bytes = compile(name).unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_caller_buffered", name, None);
    executable.write_bytes(bytes); // Shared in-function jump validation.
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn execute(name: &str, expected_allocations: usize) {
    let executable = executable(name);
    let trace = common::TempArtifact::new("laniusc_caller_buffered", "all_syscalls", None);
    let output = common::process_output_with_timeout(
        "caller-backed buffering contracts",
        crate::common::strace()
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=all", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(15),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    common::assert_command_success(name, &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}\n{events}"
    );
    let mut live = std::collections::BTreeMap::<u64, u64>::new();
    let mut allocations = 0;
    let mut launches = 0;
    let mut exits = 0;
    for line in events.lines() {
        if line.starts_with("execve(") && line.ends_with("= 0") {
            launches += 1;
        } else if let Some(arguments) = line.strip_prefix("mmap(") {
            let length: u64 = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let result = line
                .rsplit(" = ")
                .next()
                .unwrap()
                .split_whitespace()
                .next()
                .unwrap();
            let address = u64::from_str_radix(
                result.strip_prefix("0x").expect("successful allocation"),
                16,
            )
            .unwrap();
            assert!(
                length > 0 && live.insert(address, length).is_none(),
                "{events}"
            );
            allocations += 1;
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (address, rest) = arguments.split_once(',').unwrap();
            let address =
                u64::from_str_radix(address.trim().strip_prefix("0x").unwrap(), 16).unwrap();
            let length: u64 = rest.split(')').next().unwrap().trim().parse().unwrap();
            assert!(line.ends_with(" = 0"), "{events}");
            assert_eq!(live.remove(&address), Some(length), "{events}");
        } else if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            exits += 1;
        } else {
            panic!("unexpected buffering host effect: {events}");
        }
    }
    assert!(live.is_empty(), "{events}");
    assert_eq!(
        (allocations, launches, exits),
        (expected_allocations, 1, 1),
        "{events}"
    );
}
#[test]
fn caller_buffered_core_owned_seek_and_parts_execute_tiny_admission() {
    execute("admission.lani", 2);
}
#[test]
fn caller_buffered_provider_progress_errors_and_transient_eof_execute() {
    execute("contracts.lani", 0);
}
#[test]
fn caller_buffered_metadata_strides_and_consuming_lifecycle_execute() {
    execute("preflight.lani", 0);
}
#[test]
fn caller_buffered_read_write_capabilities_remain_independent() {
    execute("capabilities.lani", 2);
}

fn rejects(names: &[&str]) {
    for name in names {
        let error = compile(name).expect_err("buffering requires the endpoint capability");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic
            .primary_label
            .expect("source-local capability rejection");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        assert!(
            label
                .source_line
                .as_deref()
                .unwrap_or("")
                .contains("rejected_buffered_bound"),
            "{name}: {label:?}"
        );
    }
}
#[test]
fn caller_buffered_factories_require_read_or_write() {
    rejects(&[
        "negative_core_reader.lani",
        "negative_core_writer.lani",
        "negative_owned_reader.lani",
        "negative_owned_writer.lani",
    ]);
}
#[test]
fn caller_buffered_restoration_requires_read_or_write() {
    rejects(&[
        "negative_core_reader_restore.lani",
        "negative_core_writer_restore.lani",
        "negative_owned_reader_restore.lani",
        "negative_owned_writer_restore.lani",
    ]);
}
#[test]
fn caller_buffered_seek_requires_endpoint_seek() {
    rejects(&[
        "negative_core_reader_seek.lani",
        "negative_core_writer_seek.lani",
        "negative_owned_reader_seek.lani",
        "negative_owned_writer_seek.lani",
    ]);
}
