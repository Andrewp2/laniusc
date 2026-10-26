//! Item imports, local inference and `?` through the real standard library.

mod common;

use std::path::PathBuf;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile(fixture: &str) -> Result<Vec<u8>, String> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/language").join(fixture);
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(fixture, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .map_err(|error| error.to_string())
}

fn assert_exit(fixture: &str, code: i32) {
    let bytes = compile(fixture).unwrap_or_else(|error| panic!("{fixture}: {error}"));
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("language ergonomics", fixture, &bytes);
        assert_eq!(output.status.code(), Some(code), "{fixture}: {output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (bytes, code);
}

fn assert_rejected(fixture: &str, expected: &[&str]) {
    let error = compile(fixture).expect_err(fixture);
    for text in expected {
        assert!(error.contains(text), "{fixture}: expected `{text}` in:\n{error}");
    }
}

#[test]
fn item_imports_name_single_declarations() {
    assert_exit("item_import.lani", 7);
}

#[test]
fn an_item_import_takes_precedence_over_module_imports() {
    assert_exit("item_import_selects.lani", 7);
}

#[test]
fn an_item_import_makes_only_its_item_visible() {
    assert_rejected("item_import_only.lani", &["LNC0005", "unresolved identifier"]);
}

#[test]
fn a_name_from_two_module_imports_is_reported_as_ambiguous() {
    assert_rejected(
        "ambiguous_import.lani",
        &["LNC0005", "ambiguous imported name", "import std::stream::copy;"],
    );
}
