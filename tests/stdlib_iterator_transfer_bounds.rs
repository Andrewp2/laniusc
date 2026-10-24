//! Exact source item, sink item, and sink error bounds at the transfer call.
mod common;

use std::path::PathBuf;

fn reject(name: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/iterator_transfer_bounds")
        .join(name);
    let stdlib = root.join("stdlib");
    let result = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    });
    let error = match result {
        Err(error) => error,
        Ok(bytes) => panic!(
            "{name}: incompatible transfer bounds produced {} ELF bytes",
            bytes.len()
        ),
    };
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
    let label = diagnostic
        .primary_label
        .expect("source-local transfer bound rejection");
    assert!(label.path.ends_with(name), "{label:?}");
    assert!(
        label
            .source_line
            .as_deref()
            .unwrap_or("")
            .contains("core::iter::try_transfer_up_to<"),
        "{label:?}"
    );
}

#[test]
fn transfer_requires_the_requested_source_item_type() {
    reject("source_item.lani");
}

#[test]
fn transfer_requires_the_requested_sink_item_type() {
    reject("sink_item.lani");
}

#[test]
fn transfer_requires_the_requested_sink_error_type() {
    reject("sink_error.lani");
}
