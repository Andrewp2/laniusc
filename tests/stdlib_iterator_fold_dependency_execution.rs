//! Generic error-record inference diagnostic and executable typed-local control.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::path::PathBuf;

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/iterator_fold_dependency")
        .join(name);
    let stdlib = root.join("stdlib");
    let label = format!("generic error-record {name}");
    common::run_gpu_codegen_with_timeout(&label, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
}

fn execute(label: &str, bytes: &[u8]) {
    let output = common::run_x86_64_elf_output(label, "iterator_fold_error_record", bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn generic_error_record_typed_local_preserves_wide_error_and_success_payloads() {
    let bytes = compile("typed_local.lani").expect("the explicit E local is a valid control");
    execute("generic error-record typed local", &bytes);
}

#[test]
fn generic_error_record_inline_is_diagnostic_or_executes_after_compiler_repair() {
    match compile("inline.lani") {
        Ok(bytes) => execute("generic error-record inline repaired", &bytes),
        Err(error) => {
            // This is valid source, not a language-level rejection contract.
            // Accept its documented diagnostic while it remains unsupported;
            // a repaired compiler must execute the same payload assertions.
            let diagnostic = error.to_public_diagnostic();
            assert_eq!(diagnostic.code, "LNC0006", "{error}");
            let label = diagnostic
                .primary_label
                .expect("source-local inference diagnostic");
            assert!(label.path.ends_with("inline.lani"), "{label:?}");
            assert!(
                label
                    .source_line
                    .as_deref()
                    .unwrap_or("")
                    .contains("error:step.unwrap_err()"),
                "{label:?}"
            );
            eprintln!("valid inline generic error-record remains unsupported: {error}");
        }
    }
}
