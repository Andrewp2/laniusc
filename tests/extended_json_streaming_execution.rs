//! Borrowed JSON bytes: exact wire, stream boundaries and canonical I/O.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/extended_json_streaming")
        .join(name)
}

fn compile(name: &str) -> Vec<u8> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = fixture(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    common::run_gpu_codegen_with_timeout("borrowed JSON streaming", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("borrowed JSON streaming: {error}"))
}

#[test]
fn json_encoding_exact_wire_boundaries_copies_limits_and_read_compositions_execute() {
    let bytes = compile("contracts.lani");
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let output = common::run_x86_64_elf_output("borrowed JSON contracts", "contracts", &bytes);
    common::assert_command_success("borrowed JSON contracts", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn json_encoding_matches_ordered_ast_wire_reads_copies_and_document_snapshots() {
    let bytes = compile("model.lani");
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_json_streaming_model", "model", None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "independent ordered AST JSON wire reference",
        Command::new("python3")
            .arg("-B")
            .arg(fixture("oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(90),
    );
    common::assert_command_success("ordered AST JSON streaming model", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(
        summary,
        "json-streaming cases=978 layouts=2 admitted=672 rejected=306 reads=24774 copies=8857 invalid=3360 zero_requests=3155 observed_eof=7056 wire_bytes=32940 seed=0x150a0261110\n"
    );
    eprint!("{summary}");
}
