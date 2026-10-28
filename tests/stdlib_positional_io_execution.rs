//! Portable explicit-offset I/O, progress accounting and required capabilities.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/positional_io")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
}

#[test]
fn portable_positional_io_executes_exact_offsets_and_confirmed_failure_prefixes() {
    let bytes = compile("contracts.lani")
        .unwrap_or_else(|error| panic!("portable positional I/O contracts: {error}"));
    assert!(bytes.starts_with(b"\x7fELF"), "strict native contracts");
    let executable = common::TempArtifact::new("laniusc_positional_io", "contracts", None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let events = common::TempArtifact::new("laniusc_positional_io", "service_trace", None);
    let output = common::process_output_with_timeout(
        "scripted positional progress, admission, quotas and strided buffers",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(events.path())
            .args([
                "-e",
                "trace=mmap,mremap,munmap,brk,read,write,pread64,pwrite64,lseek,close",
                "-e",
                "signal=none",
            ])
            .arg(executable.path()),
        Duration::from_secs(12),
    );
    common::assert_command_success("portable positional I/O native contracts", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let events = fs::read_to_string(events.path()).unwrap();
    assert!(
        events.is_empty(),
        "portable helpers use no memory or host I/O services: {events}"
    );
}

#[test]
fn positional_exact_helpers_require_the_matching_explicit_offset_traits() {
    for name in [
        "negative_missing_read_at.lani",
        "negative_missing_write_at.lani",
    ] {
        let error = compile(name)
            .expect_err("sequential and opposite traits do not satisfy positional capability");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
        let label = diagnostic
            .primary_label
            .expect("explicit positional trait bound use is rejected");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        let line = label.source_line.as_deref().unwrap_or("");
        assert!(
            line.contains("core::io::") && line.contains("rejected_positional_bound"),
            "relevant positional trait-bound use in {name}: {label:?}"
        );
    }
}
