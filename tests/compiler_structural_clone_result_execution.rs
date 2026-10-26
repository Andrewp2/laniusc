//! Checked nested aggregate return layout across concrete and generic callees.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::Command,
    time::Duration,
};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("tests/fixtures/stdlib_compiler_state/structural_clone_result");
    let entry = fixtures.join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixtures],
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
}

fn execute(name: &str) {
    let bytes =
        compile(name).unwrap_or_else(|error| panic!("checked structural result {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes), "{name}");
    let executable = common::TempArtifact::new("structural_clone_result", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("structural_clone_result", "mapping_trace", None);
    let output = common::process_output_with_timeout(
        "checked structural result owner transfer",
        Command::new("timeout")
            .args(["--kill-after=1s", "3s", "strace", "-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(executable.path()),
        Duration::from_secs(5),
    );
    assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{name}: {output:?}"
    );

    // The Ok-payload case creates String+Vec; the Err-payload case creates
    // one String. Transfer itself creates no owner. Track exact addresses and
    // request lengths rather than accepting matching allocation/free counts.
    let trace = fs::read_to_string(trace.path()).unwrap();
    let mut live = BTreeMap::<String, usize>::new();
    let mut requests = Vec::new();
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let length: usize = line.split(',').nth(1).unwrap().trim().parse().unwrap();
            let address = line
                .rsplit_once(" = ")
                .unwrap()
                .1
                .split_whitespace()
                .next()
                .unwrap();
            assert!(address.starts_with("0x"), "{name}: {trace}");
            assert!(
                live.insert(address.to_owned(), length).is_none(),
                "{name}: {trace}"
            );
            requests.push(length);
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let (arguments, result) = tail.split_once(')').unwrap();
            let (address, length) = arguments.split_once(',').unwrap();
            let length: usize = length.trim().parse().unwrap();
            assert_eq!(live.remove(address.trim()), Some(length), "{name}: {trace}");
            assert_eq!(result.trim(), "= 0", "{name}: {trace}");
        } else {
            panic!("{name}: unexpected mapping event: {line}");
        }
    }
    assert_eq!(requests, [4, 8, 4], "{name}: {trace}");
    assert!(live.is_empty(), "{name}: unreleased owners: {trace}");
}

#[test]
fn a_concrete_nested_aggregate_result_retains_payload_layout() {
    execute("concrete.lani");
}

#[test]
fn b_imported_plain_generic_result_retains_payload_layout() {
    execute("imported_plain.lani");
}

#[test]
fn c_local_generic_trait_result_retains_payload_layout() {
    execute("local_trait.lani");
}

#[test]
fn d_imported_generic_trait_result_retains_payload_layout() {
    execute("imported_trait.lani");
}
