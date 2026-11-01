//! ext::cbor_stream and the cbor-to-json sample against RFC 8949 Appendix A
//! (typed by hand) and an independent Python CBOR implementation.
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
fn batch() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("cbor_batch", "tests/fixtures/stdlib_execution/cbor_oracle/cbor_batch.lani"))
}
fn cbor_to_json() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("cbor_to_json", "sample_programs/cbor_to_json.lani"))
}
fn oracle(group: &str, expected: &str) {
    let output = common::process_output_with_timeout(format!("cbor {group}"),
        Command::new("python3").arg("-B").arg("-I").arg(root().join("tests/fixtures/stdlib_execution/cbor_oracle/oracle.py"))
            .arg(group).arg(batch().path()).arg(cbor_to_json().path()), Duration::from_secs(120));
    common::assert_command_success(format!("cbor {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(summary.trim_end(), expected); eprintln!("{summary}");
}
#[test]
fn cbor_stream_matches_rfc_8949_appendix_a() {
    oracle("appendix", "cbor-appendix cases=81 python=81 copy=324/324 canon=324/324 check=324/324 deterministic=64 json=81");
}
#[test]
fn cbor_stream_round_trips_generated_items_through_python() {
    oracle("generated", "cbor-generated cases=1500 copy=6000/6000 canon=6000/6000 check=6000/6000 roundtrip=1500 duplicates=214 deterministic=949");
}
#[test]
fn cbor_stream_reports_the_python_error_and_offset_for_mutated_input() {
    oracle("mutations", "cbor-mutations cases=3000 copy=12000/12000 canon=12000/12000 check=12000/12000 rejected=2263");
}
#[test]
fn cbor_stream_enforces_depth_item_and_string_limits() {
    oracle("limits", "cbor-limits cases=2400 agree=2400 rejected=327");
}
#[test]
fn cbor_stream_decodes_sequences() {
    oracle("sequences", "cbor-sequences cases=1200 agree=1200 rejected=88");
}
#[test]
fn cbor_to_json_follows_rfc_8949_section_6_1() {
    oracle("json", "cbor-json cases=700 agree=700 converted=406 unsupported=25 invalid=69 flagged=200");
}
#[test]
fn cbor_stream_writer_flush_and_reader_contracts() {
    let exe = compile("cbor_stream_contracts", "tests/fixtures/extended/cbor_stream_contracts.lani");
    let output = common::process_output_with_timeout("cbor contracts", &mut Command::new(exe.path()), Duration::from_secs(30));
    common::assert_command_success("cbor contracts", &output);
    assert_eq!(String::from_utf8(output.stdout).unwrap(), CONTRACTS);
}
const CONTRACTS: &str = "\
integer_min 3b7fffffffffffffff\n\
unsigned_max 1bffffffffffffffff\n\
float_preserve fb3ff0000000000000\n\
float_shortest f93c00\n\
float_single fa47c35000\n\
float_double fb3ff199999999999a\n\
nan_quiet f97e00\n\
nan_payload fa7f800001\n\
subnormal_half f90001\n\
half_range error InvalidValue 0\n\
map_sorted a2616102616201\n\
map_nested a20a816278791903e8f6\n\
map_duplicate error DuplicateKey 5\n\
sticky error DuplicateKey 5\n\
map_preserve_duplicate bf01020103ff\n\
tag_chunks c1420102\n\
tag_indefinite d9d9f75f41014102ff\n\
count_short error CountMismatch 2\n\
count_ok 820102\n\
count_long error CountMismatch 2\n\
chunk_type error ChunkType 1\n\
chunk_nested error ChunkType 1\n\
odd_map error OddMap 2\n\
end_root error InvalidPlacement 0\n\
second_root error InvalidPlacement 1\n\
sequence 01f93800\n\
tag_end error InvalidPlacement 1\n\
simple_reserved error InvalidSimple 0\n\
text_utf8 error InvalidUtf8 0\n\
depth_limit error DepthLimit 1\n\
output_limit error OutputLimit 1\n\
flush 32167 3000 0 same\n\
pinned 0 3 820102\n\
reader 6 error UnexpectedEnd 13 6\n\
feed_after_finish error Finished 0\n\
input_limit error InputLimit 2\n\
";
