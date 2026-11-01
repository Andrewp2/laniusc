//! Real PNG decoding, ordered transforms and image resizing through the CLI.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, sync::OnceLock, time::Duration};

fn root() -> PathBuf { PathBuf::from(env!("CARGO_MANIFEST_DIR")) }
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/image_tool.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")), user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("image-tool resize", move || {
            pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))
        }).unwrap_or_else(|error| panic!("image-tool resize: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes), "resize consumer must produce ELF64 x86-64");
        let artifact = common::TempArtifact::new("image_resize_tool", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(group: &str, count: Option<usize>) {
    let output = common::process_output_with_timeout(format!("image resize consumer {group}"),
        Command::new("python3").arg("-B").arg(root().join("tests/fixtures/extended_image_resize_tool/oracle.py"))
            .arg(group).arg(executable().path()), Duration::from_secs(85));
    common::assert_command_success(format!("image resize consumer {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    let prefix = match count {
        Some(n) => format!("image-resize-tool-{group} cases={n} reached_allocations="),
        None => format!("image-resize-tool-{group} cases="),
    };
    assert!(summary.starts_with(&prefix), "{summary}"); eprint!("{summary}");
}
#[test]
fn image_resize_tool_png_pixels_match_shared_rational_reference() { oracle("pixels", Some(24)); }
#[test]
fn image_resize_tool_option_grammar_and_last_values_precede_input() { oracle("cli", Some(34)); }
#[test]
fn image_resize_tool_output_caps_and_late_png_errors_remain_staged() { oracle("limits", Some(10)); }
#[test]
fn image_resize_tool_reached_allocations_and_io_failures_release_all_owners() { oracle("faults", None); }
