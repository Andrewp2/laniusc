//! Source-local collection sink opt-in, exact item and exact error bounds.
mod common;

use std::path::PathBuf;

fn reject(name: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/iterator_collection_sink_bounds")
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
fn hash_map_missing_hash_is_rejected_at_transfer() {
    reject("hash_map_missing_hash.lani");
}

#[test]
fn hash_set_wrong_eq_argument_is_rejected_at_transfer() {
    reject("hash_set_wrong_eq_argument.lani");
}

#[test]
fn tree_set_wrong_ord_argument_is_rejected_at_transfer() {
    reject("tree_set_wrong_ord_argument.lani");
}

#[test]
fn hash_map_wrong_entry_module_is_rejected_at_transfer() {
    reject("hash_map_wrong_entry_module.lani");
}

#[test]
fn hash_map_wrong_sink_error_is_rejected_at_transfer() {
    reject("hash_map_wrong_sink_error.lani");
}

#[test]
fn heap_missing_ord_is_rejected_at_transfer() {
    reject("heap_missing_ord.lani");
}
