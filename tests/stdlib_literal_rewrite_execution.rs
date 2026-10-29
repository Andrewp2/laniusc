//! Bounded literal UTF-8 replacement with staged output and explicit cleanup.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, sync::OnceLock, time::Duration};

fn root() -> PathBuf { PathBuf::from(env!("CARGO_MANIFEST_DIR")) }
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/literal_rewrite.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")), user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("streaming literal rewrite", move || {
            pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))
        }).unwrap_or_else(|error| panic!("literal rewrite: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes), "literal rewrite must produce actual ELF64 x86-64");
        let artifact = common::TempArtifact::new("literal_rewrite", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(group: &str, count: Option<usize>) {
    let output = common::process_output_with_timeout(format!("literal rewrite {group}"),
        Command::new("python3").arg("-B").arg(root().join("tests/fixtures/stdlib_literal_rewrite/oracle.py"))
            .arg(group).arg(executable().path()), Duration::from_secs(85));
    common::assert_command_success(format!("literal rewrite {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    let prefix = match count {
        Some(n) => format!("literal-rewrite-{group} cases={n} reached_allocations="),
        None => format!("literal-rewrite-{group} cases="),
    };
    assert!(summary.starts_with(&prefix), "{summary}"); eprint!("{summary}");
}
#[test]
fn literal_rewrite_matches_independent_unicode_and_literal_outputs() { oracle("model", Some(29)); }
#[test]
fn literal_rewrite_validates_cli_and_utf8_before_publication() { oracle("admission", Some(30)); }
#[test]
fn literal_rewrite_checks_real_input_probe_and_output_count_limits() { oracle("limits", Some(7)); }
#[test]
fn literal_rewrite_reached_allocation_and_io_failures_release_owners() { oracle("io", None); }
