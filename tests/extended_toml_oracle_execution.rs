//! ext::toml through the TOML normalizer against Python's tomllib.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, sync::OnceLock, time::Duration};

fn root() -> PathBuf { PathBuf::from(env!("CARGO_MANIFEST_DIR")) }
fn normalizer() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/toml_normalize.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")), user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("toml normalizer", move || {
            pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))
        }).unwrap_or_else(|error| panic!("toml normalizer: {error}"));
        let artifact = common::TempArtifact::new("toml_normalize", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(group: &str, expected: &str) {
    let output = common::process_output_with_timeout(format!("toml {group}"),
        Command::new("python3").arg("-B").arg("-I").arg(root().join("tests/fixtures/stdlib_execution/toml_oracle/oracle.py"))
            .arg(group).arg(normalizer().path()), Duration::from_secs(120));
    common::assert_command_success(format!("toml {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(summary.trim_end(), expected); eprintln!("{summary}");
}
#[test]
fn toml_edge_cases_agree_with_tomllib() {
    oracle("edge", "toml-edge cases=154 agree=154 accepted=67 rejected=80 toml11_only=6 int64_only=1");
}
#[test]
fn toml_generated_documents_round_trip_through_tomllib() {
    oracle("generated", "toml-generated cases=600 agree=600 accepted=600 rejected=0 toml11_only=0 int64_only=0");
}
#[test]
fn toml_mutated_documents_agree_on_acceptance_and_values() {
    oracle("mutations", "toml-mutations cases=1000 agree=1000 accepted=221 rejected=777 toml11_only=1 int64_only=1");
}
