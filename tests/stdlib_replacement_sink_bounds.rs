//! Replacement transfer requires exact item, key and error trait identities.
mod common;

use std::path::PathBuf;

fn reject(name: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/replacement_sink_bounds")
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
            "{name}: incompatible replacement bounds produced {} ELF bytes",
            bytes.len()
        ),
    };
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
    let label = diagnostic
        .primary_label
        .expect("source-local replacement bound rejection");
    assert!(label.path.ends_with(name), "{label:?}");
    assert!(
        label
            .source_line
            .as_deref()
            .unwrap_or("")
            .contains("core::iter::try_replace_up_to<"),
        "{label:?}"
    );
}

#[test]
fn replacement_sink_rejects_nominal_tree_entry_at_hash_map() {
    reject("hash_map_wrong_entry_module.lani");
}

#[test]
fn replacement_sink_requires_hash_bound_on_key() {
    reject("hash_map_missing_hash.lani");
}

#[test]
fn replacement_sink_requires_exact_replacement_error() {
    reject("hash_map_wrong_replacement_error.lani");
}

#[test]
fn replacement_sink_requires_exact_displaced_item() {
    reject("wrong_displaced_item.lani");
}

#[test]
fn replacement_sink_requires_exact_displaced_error() {
    reject("wrong_displaced_error.lani");
}
