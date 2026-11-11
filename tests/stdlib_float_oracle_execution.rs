//! core::float_decimal (Eisel-Lemire, Grisu3, exact fallback) against Python float() and repr().
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, sync::OnceLock, time::Duration};

fn root() -> PathBuf { PathBuf::from(env!("CARGO_MANIFEST_DIR")) }
fn batch() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("tests/fixtures/stdlib_execution/float_oracle/float_batch.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots { stdlib_root: Some(root().join("stdlib")), user_roots: vec![] };
        let bytes = common::run_gpu_codegen_with_timeout("float batch", move || {
            pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))
        }).unwrap_or_else(|error| panic!("float batch: {error}"));
        let artifact = common::TempArtifact::new("float_batch", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(group: &str, expected: &str) {
    let output = common::process_output_with_timeout(format!("float {group}"),
        Command::new("python3").arg("-B").arg("-I").arg(root().join("tests/fixtures/stdlib_execution/float_oracle/oracle.py"))
            .arg(group).arg(batch().path()), Duration::from_secs(280));
    common::assert_command_success(format!("float {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(summary.trim_end(), expected); eprintln!("{summary}");
}
#[test]
fn parse_f64_matches_python_float_on_two_million_inputs() { oracle("parse64", "float-parse64 cases=2000000 agree=2000000"); }
#[test]
fn parse_f32_matches_exact_binary32_rounding() { oracle("parse32", "float-parse32 cases=500000 agree=500000"); }
#[test]
fn format_f64_matches_python_repr_digits_and_round_trips() { oracle("format64", "float-format64 cases=2000000 agree=2000000"); }
#[test]
fn format_f32_matches_exact_shortest_closest_model() { oracle("format32", "float-format32 cases=300000 agree=300000"); }
