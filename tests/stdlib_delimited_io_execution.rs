//! Buffered protocol admission and bounded byte-delimiter contracts.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::Duration,
};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/delimited_io")
        .join(name);
    let stdlib = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
}

fn execute(name: &str, allocating: bool) {
    let bytes = compile(name).unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_delimited_io", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_delimited_io", "host_effects", None);
    let output = common::process_output_with_timeout(
        "bounded delimiter native contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,mremap,munmap,brk,read,write,close",
                "-e",
                "signal=none",
            ])
            .arg(executable.path()),
        Duration::from_secs(10),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    common::assert_command_success(name, &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}\n{events}"
    );
    if !allocating {
        assert!(
            events.is_empty(),
            "core delimiter helpers have no memory or host I/O effects: {events}"
        );
        return;
    }
    let mut live = BTreeMap::new();
    let mut acquired = 0;
    for line in events.lines() {
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let (arguments, result) = arguments.split_once(")").expect("mmap arguments");
            let length = arguments
                .split(',')
                .nth(1)
                .unwrap()
                .trim()
                .parse::<usize>()
                .unwrap();
            let address = result.trim().strip_prefix("= ").unwrap();
            assert!(
                address.starts_with("0x"),
                "successful fixed-buffer ownership: {line}"
            );
            assert!(
                live.insert(address.to_string(), length).is_none(),
                "live allocation reused: {events}"
            );
            acquired += 1;
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let (address, length) = arguments.split_once(',').unwrap();
            let length = length.trim().parse::<usize>().unwrap();
            assert_eq!(result.trim(), "= 0", "{events}");
            assert_eq!(
                live.remove(address),
                Some(length),
                "release must match address and size: {events}"
            );
        } else {
            panic!("unexpected delimiter service: {events}");
        }
    }
    assert_eq!(
        acquired, 1,
        "only the actual buffered reader owns storage: {events}"
    );
    assert!(live.is_empty(), "all owned storage released: {events}");
}

#[test]
fn bufread_only_generic_helpers_and_real_readers_execute_binary_admission() {
    execute("admission.lani", true);
}

#[test]
fn delimiter_contracts_execute_binary_limits_budgets_and_distinct_failure_progress() {
    execute("contracts.lani", false);
}

#[test]
fn delimiter_helpers_require_bufread_instead_of_sequential_read() {
    for name in ["negative_read_until.lani", "negative_skip_until.lani"] {
        let error = compile(name).expect_err("Read alone does not satisfy BufRead");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic
            .primary_label
            .expect("explicit BufRead requirement");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        let line = label.source_line.as_deref().unwrap_or("");
        assert!(
            line.contains("core::io::") && line.contains("rejected_bufread_bound"),
            "relevant BufRead use: {label:?}"
        );
    }
}
