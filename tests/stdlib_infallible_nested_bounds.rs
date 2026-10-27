//! Ordinary nested iteration requires infallible policies and exact items.
mod common;

use std::path::PathBuf;

fn reject(name: &str, helper: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/infallible_nested_bounds")
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
            "{name}: incompatible ordinary nested bounds produced {} ELF bytes",
            bytes.len()
        ),
    };
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
    let label = diagnostic
        .primary_label
        .expect("source-local ordinary nested bound rejection");
    assert!(label.path.ends_with(name), "{label:?}");
    assert!(
        label.source_line.as_deref().unwrap_or("").contains(helper),
        "{label:?}"
    );
}

#[test]
fn ordinary_flatten_rejects_fallible_retirement() {
    reject("fallible_retirement.lani", "core::iter::flatten<");
}

#[test]
fn ordinary_flat_map_rejects_fallible_mapper() {
    reject("fallible_mapper.lani", "core::iter::flat_map<");
}

#[test]
fn ordinary_flatten_rejects_wrong_inner_item() {
    reject("wrong_inner_item.lani", "core::iter::flatten<");
}
