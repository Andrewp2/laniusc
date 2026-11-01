//! Resumable decompressor fixed workspace and actual owned decode failures.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};
fn root() -> PathBuf { PathBuf::from(env!("CARGO_MANIFEST_DIR")) }
fn execute(group: &str, fixture: &str) {
    let entry = root().join("tests/fixtures/extended/inflate_stream_resources").join(fixture);
    let roots = laniusc_compiler::compiler::EntrySourceRoots { stdlib_root: Some(root().join("stdlib")), user_roots: vec![root().join("extended")] };
    let bytes = common::run_gpu_codegen_with_timeout("streaming inflate resources", move || pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))).unwrap();
    assert!(common::x86_jumps::is_x86_64_executable(&bytes), "resource fixture must produce actual ELF64 x86-64");
    let exe = common::TempArtifact::new("inflate_stream_resources", "executable", None); exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let result = common::process_output_with_timeout(format!("inflate resource {group}"), Command::new("python3").arg("-B").arg(root().join("tests/fixtures/extended/inflate_stream_resources/oracle.py")).arg(group).arg(exe.path()), Duration::from_secs(85));
    common::assert_command_success(format!("inflate resource {group}"), &result); assert!(result.stderr.is_empty(), "{result:?}");
    let summary = String::from_utf8(result.stdout).unwrap(); assert!(summary.starts_with(&format!("inflate-stream-resources-{group} processes=")), "{summary}"); eprint!("{summary}");
}
#[test]
fn resumable_inflate_reuses_fixed_workspace_across_formats_errors_and_megabyte_streams() { execute("stream", "stream.lani"); }
#[test]
fn owned_inflate_reached_workspace_and_output_allocation_failures_release_all_private_owners() { execute("owned", "owned.lani"); }
