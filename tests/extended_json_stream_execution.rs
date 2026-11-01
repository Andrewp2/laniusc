//! Streaming JSON tokenizer/writer, jq-lite and csv-to-json against Python's json and csv modules.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, sync::OnceLock, time::Duration};

fn root() -> PathBuf { PathBuf::from(env!("CARGO_MANIFEST_DIR")) }
fn compile(name: &'static str, entry: &'static str) -> common::TempArtifact {
    let entry = root().join(entry);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")), user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    }).unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes), "{name} must produce actual ELF64 x86-64");
    let artifact = common::TempArtifact::new(name, "executable", None);
    artifact.write_bytes(bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}
fn jq_lite() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("jq_lite", "sample_programs/jq_lite.lani"))
}
fn contracts() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("json_stream_contracts", "tests/fixtures/extended/json_stream_contracts.lani"))
}
fn csv_to_json() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("csv_to_json", "sample_programs/csv_to_json.lani"))
}
fn oracle(script: &str, group: &str, exe: &common::TempArtifact, prefix: &str) {
    let output = common::process_output_with_timeout(format!("{script} {group}"),
        Command::new("python3").arg("-B").arg("-I").arg(root().join(format!("tests/fixtures/stdlib_execution/{script}/oracle.py")))
            .arg(group).arg(exe.path()), Duration::from_secs(120));
    common::assert_command_success(format!("{script} {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(summary.starts_with(prefix), "{summary}");
    eprint!("{summary}");
}
#[test]
fn jq_lite_agrees_with_python_json_on_suite_cases() { oracle("jq_lite", "suite", jq_lite(), "jq-lite-suite cases=272 agree=272 "); }
#[test]
fn jq_lite_agrees_on_generated_and_mutated_documents() {
    oracle("jq_lite", "generated", jq_lite(), "jq-lite-generated cases=400 agree=400 ");
    oracle("jq_lite", "mutations", jq_lite(), "jq-lite-mutations cases=600 agree=600 ");
    oracle("jq_lite", "chunks", jq_lite(), "jq-lite-chunks cases=32 agree=32 ");
}
#[test]
fn jq_lite_path_queries_match_python_selection() { oracle("jq_lite", "paths", jq_lite(), "jq-lite-paths cases=300 agree=300 "); }
#[test]
fn jq_lite_reports_exact_typed_errors_and_offsets() { oracle("jq_lite", "errors", jq_lite(), "jq-lite-errors cases=30 agree=30 "); }
#[test]
fn json_stream_bytewise_feeds_and_writer_contracts() {
    oracle("jq_lite", "bytewise", contracts(), "jq-lite-bytewise cases=602 agree=602 ");
    oracle("jq_lite", "writer", contracts(), "jq-lite-writer cases=1 agree=1 ");
}
#[test]
fn csv_to_json_agrees_with_python_csv() {
    oracle("csv_to_json", "rfc", csv_to_json(), "csv-to-json-rfc cases=48 agree=48");
    oracle("csv_to_json", "generated", csv_to_json(), "csv-to-json-generated cases=502 agree=502");
    oracle("csv_to_json", "invalid", csv_to_json(), "csv-to-json-invalid cases=15 rejected=15 ");
}
