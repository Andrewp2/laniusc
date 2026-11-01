//! look(1)-style prefix, neighbor and inclusive-range lookup over borrowed Text keys.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, sync::OnceLock, time::Duration};

fn root() -> PathBuf { PathBuf::from(env!("CARGO_MANIFEST_DIR")) }
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/look_words.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")), user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("look words", move || {
            pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))
        }).unwrap_or_else(|error| panic!("look words: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes), "look words must produce actual ELF64 x86-64");
        let artifact = common::TempArtifact::new("look_words", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(group: &str, count: Option<usize>) {
    let output = common::process_output_with_timeout(format!("look words {group}"),
        Command::new("python3").arg("-B").arg(root().join("tests/fixtures/stdlib_execution/look_words/oracle.py"))
            .arg(group).arg(executable().path()), Duration::from_secs(85));
    common::assert_command_success(format!("look words {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    let prefix = match count {
        Some(n) => format!("look-words-{group} cases={n}\n"),
        None => format!("look-words-{group} cases=52 reached_allocation_failures="),
    };
    assert!(summary.starts_with(&prefix), "{summary}"); eprint!("{summary}");
}
#[test]
fn look_words_matches_independent_sorted_prefix_neighbor_and_range_reference() { oracle("model", Some(46)); }
#[test]
fn look_words_rejects_usage_invalid_utf8_and_argument_caps_before_output() { oracle("admission", Some(22)); }
#[test]
fn look_words_enforces_exact_input_word_and_output_caps() { oracle("limits", Some(6)); }
#[test]
fn look_words_reports_output_input_and_address_space_allocation_failures() { oracle("faults", None); }
