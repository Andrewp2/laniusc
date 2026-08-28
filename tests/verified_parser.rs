mod common;

use std::path::PathBuf;

use laniusc_compiler::compiler::compile_entry_to_wasm_with_source_root;

#[test]
fn verified_earley_recognizer_runs_general_grammar_cases() {
    common::require_node();
    let repository = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = repository.join("verified_compiler/tests/parser_recognizer.lani");
    let source_root = repository.join("verified_compiler/src");
    let wasm = common::run_gpu_codegen_with_timeout("verified Earley recognizer", move || {
        pollster::block_on(compile_entry_to_wasm_with_source_root(
            entry,
            source_root,
        ))
    })
    .expect("compile the verified parser test program");

    let status = common::run_wasm_main_return_with_node(
        "verified Earley recognizer",
        "verified_earley_recognizer",
        &wasm,
    );
    assert_eq!(status, 0, "the first failing parser contract is the exit code");
}
