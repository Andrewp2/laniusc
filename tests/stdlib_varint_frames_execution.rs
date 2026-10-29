//! Native checked varint framing, relative cursor chaining and full-width sums.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Stdio},
    time::Duration,
};

fn execute(name: &str, expected: &[u8]) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs").join(format!("{name}.lani"));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(
        common::x86_jumps::is_x86_64_executable(&bytes),
        "{name} requires an actual ELF64 x86-64 executable"
    );
    let executable = common::TempArtifact::new("native_varint_frame", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        name,
        Command::new(executable.path()).stdin(Stdio::null()),
        Duration::from_secs(5),
    );
    common::assert_command_success(name, &output);
    assert_eq!(
        output.stdout, expected,
        "{name}: exact full-width decimal sum"
    );
    assert!(output.stderr.is_empty(), "{name}: {output:?}");
}

#[test]
fn native_unsigned_varint_frame_chains_checked_decodes_and_preserves_full_width_sum() {
    execute("varint_frame_sum", b"4294967606\n");
}

#[test]
fn native_signed_varint_frame_chains_checked_decodes_and_preserves_full_width_sum() {
    execute("varint_signed_frame_sum", b"-4294967321\n");
}
