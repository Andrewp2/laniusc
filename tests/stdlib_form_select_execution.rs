//! Binary form selection with ordered duplicate fields and bounded generic copying.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, sync::OnceLock, time::Duration};

fn root() -> PathBuf { PathBuf::from(env!("CARGO_MANIFEST_DIR")) }
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/form_select.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")), user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("binary form selector", move || {
            pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))
        }).unwrap_or_else(|error| panic!("form selector: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes), "form selector must produce actual ELF64 x86-64");
        let artifact = common::TempArtifact::new("form_select", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(group: &str, count: Option<usize>) {
    let output = common::process_output_with_timeout(format!("form selector {group}"),
        Command::new("python3").arg("-B").arg(root().join("tests/fixtures/stdlib_execution/form_select/oracle.py"))
            .arg(group).arg(executable().path()), Duration::from_secs(85));
    common::assert_command_success(format!("form selector {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    let prefix = match count {
        Some(n) => format!("form-select-{group} cases={n} reached_allocations="),
        None => format!("form-select-{group} cases="),
    };
    assert!(summary.starts_with(&prefix), "{summary}"); eprint!("{summary}");
}
#[test]
fn form_select_matches_independent_binary_canonical_selection() { oracle("model", Some(32)); }
#[test]
fn form_select_rejects_argument_count_and_size_before_input() { oracle("admission", Some(5)); }
#[test]
fn form_select_observes_input_pair_key_and_selected_output_limits() { oracle("limits", Some(10)); }
#[test]
fn form_select_reached_allocation_io_and_copy_call_failures_release_owners() { oracle("io", None); }
