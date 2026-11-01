//! Native integers and IEEE bits over caller-backed bytes in both orders.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/native_endian")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("native endian {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_native_endian", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

#[test]
fn native_endian_literal_vectors_preserve_signed_and_ieee_bits_without_memory_services() {
    let executable = executable("contracts.lani");
    let trace = common::TempArtifact::new("laniusc_native_endian", "memory_trace", None);
    let output = common::process_output_with_timeout(
        "native endian literal bytes, signed values, IEEE payloads and logical admission",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
            .arg(executable.path()),
        Duration::from_secs(12),
    );
    common::assert_command_success("native endian direct contracts", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let trace = fs::read_to_string(trace.path()).unwrap();
    assert!(
        trace.is_empty(),
        "caller-backed byte operations use no memory services: {trace}"
    );
}

#[test]
fn native_endian_valid_logical_extents_over_short_physical_backing_trap() {
    for name in [
        "read_u64_physical_bounds.lani",
        "write_i64_physical_bounds.lani",
        "read_f32_physical_bounds.lani",
        "write_f64_physical_bounds.lani",
    ] {
        let executable = executable(name);
        let output = common::process_output_with_timeout(
            name,
            &mut Command::new(executable.path()),
            Duration::from_secs(5),
        );
        assert_eq!(
            output.status.code(),
            Some(101),
            "native bounds trap in {name}: {output:?}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{name}: {output:?}"
        );
    }
}
