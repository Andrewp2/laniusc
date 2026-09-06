mod common;

use std::path::PathBuf;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_root;

#[test]
fn verified_earley_recognizer_runs_general_grammar_cases() {
    let repository = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = repository.join("verified_compiler/tests/parser_recognizer.lani");
    let source_root = repository.join("verified_compiler/src");
    let elf = common::run_gpu_codegen_with_timeout("verified Earley recognizer", move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_root(
            entry,
            source_root,
        ))
    })
    .expect("compile the verified parser test program");

    let result = common::run_x86_64_elf_output(
        "verified Earley recognizer",
        "verified_earley_recognizer",
        &elf,
    );
    assert!(result.status.success(), "native parser failed: {result:?}");
}
