//! Pending reducer for generic iterator Option assignment across branches.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::path::PathBuf;

#[test]
fn iterator_filter_option_assignment_matches_direct_binding() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_compiler_state/iterator_selection_assignment/reducer.lani");
    let stdlib = root.join("stdlib");
    let bytes =
        common::run_gpu_codegen_with_timeout("iterator Option assignment reducer", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .expect("the generic iterator assignment reducer should compile");
    let output = common::run_x86_64_elf_output(
        "iterator Option assignment reducer",
        "iterator_option_assignment",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        output.stdout,
        [65, 1, 66, 1, 67, 1, 68, 0, 2, 1, 1, 0, 0, 1],
        "markers: A/direct empty, B/first-branch empty, C/second-branch empty, D/Some(0); \
         source calls(first, second, some); callback calls(first, second, some)"
    );
}

#[test]
fn iterator_assignment_context_rejects_an_incompatible_actual_item_type() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(
        "tests/fixtures/stdlib_compiler_state/iterator_selection_assignment/reject_incompatible_assignment.lani",
    );
    let stdlib = root.join("stdlib");
    let compiled = common::run_gpu_codegen_with_timeout(
        "incompatible iterator result assignment",
        move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        },
    );
    let error = match compiled {
        Ok(bytes) => panic!(
            "incompatible iterator result assignment emitted {} bytes of ELF",
            bytes.len()
        ),
        Err(error) => error,
    };
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0006", "{error}");
    let label = diagnostic.primary_label.expect("source assignment label");
    assert!(
        label.path.ends_with("reject_incompatible_assignment.lani"),
        "{label:?}"
    );
    assert_eq!(
        label.source_line.as_deref().map(str::trim),
        Some("item = first.next();"),
        "{label:?}"
    );
}

#[test]
fn generic_option_assignment_forms_preserve_both_variant_predicates() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_compiler_state/iterator_selection_assignment/controls.lani");
    let stdlib = root.join("stdlib");
    let bytes =
        common::run_gpu_codegen_with_timeout("generic Option assignment forms", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .expect("compile direct, unconditional and conditional generic result assignments");
    let output = common::run_x86_64_elf_output(
        "generic Option assignment forms",
        "iterator_assignment_forms",
        &bytes,
    );
    let mut expected = Vec::new();
    for label in b'A'..=b'H' {
        let present = label >= b'E';
        expected.extend([
            label,
            u8::from(!present),
            u8::from(present),
            1,
            u8::from(present),
        ]);
    }
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout, expected,
        "direct/unconditional/both branch assignments of None and Some(0); one source pull and predicate only for Some");
}
