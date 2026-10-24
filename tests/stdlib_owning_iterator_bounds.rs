//! Explicit Destroy<T> and owning source item constraints.
mod common;

use std::path::PathBuf;

fn reject(name: &str, factory: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/owning_iterator_bounds")
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
        label.source_line.as_deref().unwrap_or("").contains(factory),
        "{label:?}"
    );
}

#[test]
fn owning_vec_destroy_helper_requires_destroy_for_the_actual_item() {
    reject(
        "vec_missing_destroy.lani",
        "alloc::clone::destroy_vec_iter<",
    );
}
#[test]
fn owning_deque_destroy_helper_requires_the_exact_destroy_argument() {
    reject(
        "deque_wrong_destroy_item.lani",
        "alloc::clone::destroy_deque_iter<",
    );
}
#[test]
fn transfer_requires_the_actual_owning_iterator_item() {
    reject(
        "transfer_wrong_owning_item.lani",
        "core::iter::try_transfer_up_to<",
    );
}
