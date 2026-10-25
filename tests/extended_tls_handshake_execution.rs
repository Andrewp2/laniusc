// Two native programs: ordinary imported use and a batched Python struct model.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    fs::File,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::Duration,
};
fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended/tls_handshake")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_tls_handshake", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(label: &str, exe: &common::TempArtifact, input: Option<&common::TempArtifact>) -> Vec<u8> {
    let trace = common::TempArtifact::new("laniusc_tls_handshake", label, None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"])
        .arg(exe.path());
    if let Some(input) = input {
        command.stdin(File::open(input.path()).unwrap());
    }
    let output = common::process_output_with_timeout(label, &mut command, Duration::from_secs(20));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        events.is_empty(),
        "borrowed codecs must allocate/release no backing: {events}"
    );
    output.stdout
}
#[test]
fn complete_borrowed_tls13_wire_codecs_execute_without_error_projection() {
    let exe = executable("plain.lani");
    assert!(run("ordinary TLS handshake consumer", &exe, None).is_empty());
}
#[test]
fn tls13_handshake_frames_bodies_cursors_and_atomic_writers_match_struct_model() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let input = common::TempArtifact::new("laniusc_tls_handshake", "model_input", None);
    let expected = common::TempArtifact::new("laniusc_tls_handshake", "model_expected", None);
    let records = common::TempArtifact::new("laniusc_tls_handshake", "model_records", None);
    let generated = common::process_output_with_timeout(
        "independent TLS framing/struct oracle",
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/tls_handshake/oracle.py"))
            .arg(input.path())
            .arg(expected.path())
            .arg(records.path()),
        Duration::from_secs(10),
    );
    assert!(
        generated.status.success() && generated.stderr.is_empty(),
        "{generated:?}"
    );
    let expected = std::fs::read(expected.path()).unwrap();
    let records = std::fs::read_to_string(records.path()).unwrap();
    let records: Vec<_> = records.lines().collect();
    assert!(!records.is_empty());
    let ends: Vec<usize> = records
        .iter()
        .map(|record| record.rsplit_once('\t').unwrap().1.parse().unwrap())
        .collect();
    assert_eq!(ends.last(), Some(&expected.len()));
    let exe = executable("model.lani");
    let actual = run("TLS handshake struct and cursor model", &exe, Some(&input));
    if actual != expected {
        let at = actual
            .iter()
            .zip(&expected)
            .position(|(a, b)| a != b)
            .unwrap_or(actual.len().min(expected.len()));
        let case = ends.partition_point(|end| *end <= at);
        let start = if case == 0 { 0 } else { ends[case - 1] };
        let end = ends.get(case).copied().unwrap_or(start);
        panic!("TLS handshake case {case} {:?}, response byte {}, actual {:?}, expected {:?}; total lengths {} vs {}",records.get(case),at-start,actual.get(start..end.min(actual.len())),expected.get(start..end.min(expected.len())),actual.len(),expected.len());
    }
    eprintln!(
        "accepted {} TLS handshake model commands in one native process",
        records.len()
    );
}
