mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn x86_sample_programs_compile_run_and_match_stdout() {
    for sample in common::sample_programs::load_sample_programs() {
        if !sample.checked_for_target("x86_64") {
            continue;
        }

        let name = sample.name().to_owned();
        let path = sample.path().to_path_buf();
        let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
        let context = format!("x86 sample {name}");
        let bytes = common::run_gpu_codegen_with_timeout(&context, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib_root))
        })
        .unwrap_or_else(|err| panic!("{context} should compile to x86_64: {err}"));

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let stdout = common::run_x86_64_elf(&context, &format!("x86_sample_{name}"), &bytes);
            sample.assert_stdout_eq("x86", &stdout);
        }
    }
}
