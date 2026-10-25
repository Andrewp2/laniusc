#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
    time::Duration,
};
fn fixture(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!(
        "tests/fixtures/stdlib_foundation/adler32_{name}.lani"
    ));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|e| panic!("{name}: {e}"));
    let exe = common::TempArtifact::new("laniusc_adler32", name, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("adler32", command, Duration::from_secs(10))
}
fn checked(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
#[test]
fn adler_contracts_execute_strided_views_state_validation_and_u32_chunk_boundaries_without_allocation()
 {
    let exe = fixture("contracts");
    let trace = common::TempArtifact::new("laniusc_adler32", "trace", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap",
            "-e",
            "inject=mmap:error=ENOMEM:when=1+",
        ])
        .arg(exe.path()));
    checked(&output);
    assert!(output.stdout.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}
#[test]
fn adler_checksums_and_chunked_updates_match_zlib_at_reduction_boundaries_and_large_sizes() {
    let exe = fixture("model");
    let input = common::TempArtifact::new("laniusc_adler32", "input", None);
    let mut vectors = vec![
        b"".to_vec(),
        b"Wikipedia".to_vec(),
        b"123456789".to_vec(),
        (0..=255).collect(),
    ];
    for length in [1, 5551, 5552, 5553, 11104, 16656, 65536, 1048576] {
        vectors.push(vec![255; length]);
        vectors.push((0..length).map(|i| ((i * 37) ^ (i / 256)) as u8).collect());
    }
    for (case, bytes) in vectors.iter().enumerate() {
        input.write_bytes(bytes);
        for state in [1u32, 0, 0xfff0fff0] {
            let split = if bytes.len() > 5553 {
                [1, 5551, 5552, 5553, bytes.len()][case % 5]
            } else {
                bytes.len() / 2
            };
            let output = run(Command::new(exe.path())
                .args([state.to_string(), split.to_string()])
                .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
            checked(&output);
            let actual: Vec<u32> = std::str::from_utf8(&output.stdout)
                .unwrap()
                .split_whitespace()
                .map(|s| s.parse().unwrap())
                .collect();
            let reference=run(Command::new("python3").args(["-c","import sys,zlib; data=sys.stdin.buffer.read(); print(zlib.adler32(data),zlib.adler32(data,int(sys.argv[1])))",&state.to_string()]).stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
            checked(&reference);
            let expected: Vec<u32> = std::str::from_utf8(&reference.stdout)
                .unwrap()
                .split_whitespace()
                .map(|s| s.parse().unwrap())
                .collect();
            assert_eq!(
                actual,
                [expected[0], expected[1], expected[1]],
                "case={case} state={state} split={split} length={}",
                bytes.len()
            );
        }
    }
}
