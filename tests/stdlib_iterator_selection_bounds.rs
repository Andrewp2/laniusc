//! Exact callback type bounds for iterator selection and folding factories.
mod common;

use std::path::PathBuf;

fn reject(name: &str, factory: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/iterator_selection_bounds")
        .join(name);
    let stdlib = root.join("stdlib");
    let error = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .expect_err("the factory requires the exact callback type arguments");
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
    let label = diagnostic
        .primary_label
        .expect("bound rejection retains its source call");
    assert!(label.path.ends_with(name), "{label:?}");
    let line = label.source_line.as_deref().unwrap_or("");
    assert!(line.contains(factory), "{label:?}");
}

#[test]
fn filter_requires_a_boolean_mapper_result() {
    reject("filter_integer_predicate.lani", "core::iter::filter<");
}

#[test]
fn filter_map_requires_the_requested_optional_item() {
    reject("filter_map_wide_item.lani", "core::iter::filter_map<");
}

#[test]
fn fold_requires_the_requested_accumulator_type() {
    reject("fold_unsigned_accumulator.lani", "core::iter::fold<");
}

#[test]
fn try_fold_requires_the_requested_error_type() {
    reject("try_fold_wide_error.lani", "core::iter::try_fold<");
}
