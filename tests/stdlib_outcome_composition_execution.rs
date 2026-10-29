//! Eager type-changing outcomes and specialized flatten/transpose methods.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/outcome_composition")
        .join(name);
    let stdlib = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
}

fn execute(name: &str) {
    let bytes = compile(name).unwrap_or_else(|error| panic!("outcome composition {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_outcome_composition", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_outcome_composition", "service_trace", None);
    let output = common::process_output_with_timeout(
        name,
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
        Duration::from_secs(12),
    );
    common::assert_command_success(name, &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let trace = fs::read_to_string(trace.path()).unwrap();
    assert!(
        trace.is_empty(),
        "pure shallow outcome operations use no memory or I/O services: {trace}"
    );
}

#[test]
fn specialized_outcome_methods_admit_native_flatten_and_imported_transpose() {
    execute("admission.lani");
}

#[test]
fn eager_outcome_tables_preserve_cross_type_payloads_and_original_copies() {
    execute("contracts.lani");
}

#[test]
fn outcome_composition_rejects_shared_type_mismatches_and_wrong_nested_shapes() {
    for name in [
        "negative_and_error_type.lani",
        "negative_or_success_type.lani",
        "negative_result_flatten_shape.lani",
        "negative_option_flatten_shape.lani",
        "negative_transpose_to_result_shape.lani",
        "negative_transpose_to_option_shape.lani",
    ] {
        let error = compile(name)
            .expect_err("composition retains its shared types and required nested shapes");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{name}: {error}");
        let label = diagnostic
            .primary_label
            .expect("rejected typed composition call has a source location");
        assert!(label.path.ends_with(name), "{name}: {label:?}");
        let line = label.source_line.as_deref().unwrap_or("");
        assert!(
            line.contains("rejected_outcome_shape"),
            "relevant typed call in {name}: {label:?}"
        );
    }
}
