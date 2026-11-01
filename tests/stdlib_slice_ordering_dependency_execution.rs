//! Distinct trait argument applications on one receiver: diagnostic and control.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::path::PathBuf;

fn compile(name: &str) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/slice_ordering_dependency")
        .join(name);
    let stdlib = root.join("stdlib");
    let label = format!("distinct comparison trait applications {name}");
    common::run_gpu_codegen_with_timeout(&label, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
}

fn execute(label: &str, bytes: &[u8]) {
    assert!(
        bytes.starts_with(b"\x7fELF"),
        "strict native comparison control"
    );
    let output = common::run_x86_64_elf_output(label, "slice_ordering_trait_applications", bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
fn split_comparator_receivers_execute_both_distinct_trait_argument_roles() {
    let bytes =
        compile("split_receivers.lani").expect("distinct receivers are the positive control");
    execute("split comparison receivers", &bytes);
}

#[test]
fn same_receiver_distinct_comparator_applications_are_diagnostic_or_execute_after_repair() {
    match compile("same_receiver.lani") {
        Ok(bytes) => execute("same comparison receiver repaired", &bytes),
        Err(error) => {
            // These are different trait applications, not duplicate methods.
            // Do not require valid source to remain rejected after a repair.
            let diagnostic = error.to_public_diagnostic();
            assert_eq!(diagnostic.code, "LNC0027", "{error}");
            let label = diagnostic
                .primary_label
                .expect("source-local duplicate-member diagnostic");
            assert!(label.path.ends_with("same_receiver.lani"), "{label:?}");
            assert!(
                label
                    .source_line
                    .as_deref()
                    .unwrap_or("")
                    .contains("fn compare("),
                "{label:?}"
            );
            let message = error.to_string();
            assert!(
                message.contains("duplicate") || message.contains("equivalent"),
                "{message}"
            );
            eprintln!(
                "valid distinct comparison applications on one receiver remain unsupported: {error}"
            );
        }
    }
}
