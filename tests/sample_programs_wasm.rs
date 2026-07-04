mod common;

use std::path::PathBuf;

use laniusc_compiler::compiler::compile_entry_to_wasm_with_stdlib;

#[test]
fn wasm_sample_programs_compile_run_and_match_stdout() {
    common::require_node();
    let stdlib_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");

    for sample in common::sample_programs::load_sample_programs() {
        if !sample.checked_for_target("wasm") {
            continue;
        }
        if !sample.selected_by_env_filter() {
            continue;
        }

        let name = sample.name().to_owned();
        let path = sample.path().to_path_buf();
        let stdlib_root = stdlib_root.clone();
        let context = format!("wasm sample {name}");
        let bytes = common::run_gpu_codegen_with_timeout(&context, move || {
            pollster::block_on(compile_entry_to_wasm_with_stdlib(&path, &stdlib_root))
        })
        .unwrap_or_else(|err| panic!("{context} should compile to WASM: {err}"));

        let initial_files = sample.wasm_initial_files();
        let result = common::run_wasm_main_with_node_and_files(
            &context,
            &format!("wasm_sample_{name}"),
            &bytes,
            &initial_files,
        );
        sample.assert_exit_code_eq("wasm", result.exit_code);
        sample.assert_stdout_eq("wasm", &result.stdout);
        sample.assert_output_files_eq_virtual(
            "wasm",
            result
                .files
                .iter()
                .map(|(path, bytes)| (path.as_str(), bytes.as_slice())),
        );
    }
}
