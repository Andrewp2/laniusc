//! ext::msgpack and the msgpack-json sample against the installed Python msgpack
//! package, a hand-typed format table and an independent Python model.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;
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
    EXE.get_or_init(|| compile("msgpack_batch", "tests/fixtures/stdlib_execution/msgpack_oracle/msgpack_batch.lani"))
}
fn msgpack_json() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("msgpack_json", "sample_programs/msgpack_json.lani"))
}
fn oracle(group: &str, expected: &str) {
    let output = common::process_output_with_timeout(format!("msgpack {group}"),
        Command::new("python3").arg("-B").arg("-I").arg(root().join("tests/fixtures/stdlib_execution/msgpack_oracle/oracle.py"))
            .arg(group).arg(batch().path()).arg(msgpack_json().path()), Duration::from_secs(120));
    common::assert_command_success(format!("msgpack {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert_eq!(summary.trim_end(), expected); eprintln!("{summary}");
}
#[test]
fn msgpack_matches_the_format_table_and_msgpack_python() { oracle("spec", "msgpack-spec cases=76 typed=76/76 copy=304/304 check=304/304 msgpack_python=76/76"); }
#[test]
fn msgpack_round_trips_generated_values() { oracle("generated", "msgpack-generated cases=1500 copy=6000/6000 check=6000/6000 msgpack_python=1500/1500 packb=888/888 canonical=1288"); }
#[test]
fn msgpack_reports_the_model_error_and_offset_for_mutated_input() { oracle("mutations", "msgpack-mutations cases=3000 copy=12000/12000 check=12000/12000 msgpack_python=3000/3000 rejected=2192"); }
#[test]
fn msgpack_enforces_depth_item_and_string_limits() { oracle("limits", "msgpack-limits cases=2398 agree=2398 rejected=398"); }
#[test]
fn msgpack_decodes_concatenated_streams_like_unpacker() { oracle("sequences", "msgpack-sequences cases=1200 agree=1200 unpacker=600/600 rejected=83"); }
#[test]
fn msgpack_json_converts_both_directions() { oracle("json", "msgpack-json cases=900 agree=900 converted=261 empty=39 rejected=200 from_json=400/400"); }
#[test]
fn msgpack_writer_flush_and_reader_contracts() {
    let exe = compile("msgpack_contracts", "tests/fixtures/extended/msgpack_contracts.lani");
    let output = common::process_output_with_timeout("msgpack contracts", &mut Command::new(exe.path()), Duration::from_secs(30));
    common::assert_command_success("msgpack contracts", &output);
    assert_eq!(String::from_utf8(output.stdout).unwrap(), CONTRACTS);
}
const CONTRACTS: &str = "\
integers 96ffd0df7fcc80d38000000000000000cfffffffffffffffff\n\
floats 92ca3fc00000cb3ff8000000000000\n\
bin_header c50100000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff\n\
ext_fixed 93d60501020304c70380010203c70001\n\
timestamps 94d6ff00000001d7ff0000001400000001c70cff000000000000000400000000c70cff3b9ac9fffffffffffffffffb\n\
timestamp_range error InvalidValue 0\n\
patched de001000900190029003900490059006900790089009900a900b900c900d900e900f90\n\
count_short error CountMismatch 2\n\
count_ok 92c0c0\n\
count_long error CountMismatch 3\n\
odd_map error OddMap 1\n\
end_root error InvalidPlacement 0\n\
str_utf8 error InvalidUtf8 0\n\
stream_roots c0c3\n\
depth_limit error DepthLimit 0\n\
output_limit error OutputLimit 1\n\
timestamp_decode -5 999999999\n\
flush 20457 3000 0 same\n\
pinned 0 3 92c0c0\n\
reader 5 error UnexpectedEnd 11 5\n\
feed_after_finish error Finished 0\n\
input_limit error InputLimit 2\n\
";
