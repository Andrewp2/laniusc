//! Closures bind to the traits of `core::function`, a language item: the
//! type checker resolves its paths without an import, and the desugaring
//! inserts no import into the closure's file.

use crate::common;

use std::path::PathBuf;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

const NO_IMPORT: &str = "\
fn apply<M>(mapper: &M, value: i32) -> i32 where M: core::function::Mapper<i32, i32> {
    return mapper.apply(value);
}

fn main() -> i32 {
    let k: i32 = 3;
    return apply(|x: i32| x * k, 2) - 6;
}
";

#[test]
fn a_closure_in_a_file_without_imports_compiles_and_runs() {
    let entry = common::TempArtifact::new("closures", "no_import", Some("lani"));
    entry.write_str(NO_IMPORT);
    let path = entry.path().to_path_buf();
    let stdlib = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("closure without imports", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
    })
    .unwrap_or_else(|error| panic!("closure without imports: {error:?}"));
    let output = common::run_x86_64_elf_output("closure without imports", "closures", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}

#[test]
fn a_closure_in_a_build_without_core_reports_the_missing_trait_module_at_its_bar() {
    let source = "fn main() -> i32 {\n    let k: i32 = 3;\n    let f = |x: i32| x * k;\n    return 0;\n}\n";
    let error = common::run_gpu_codegen_with_timeout("closure without core", move || {
        let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new())
            .expect("GPU compiler");
        pollster::block_on(compiler.compile_source_to_x86_64(source))
    })
    .expect_err("a closure without core::function must not compile");
    let diagnostic = error.to_public_diagnostic();
    let label = diagnostic.primary_label.clone().unwrap_or_else(|| panic!("unlocated: {error:?}"));
    assert_eq!((label.line, label.column), (3, 13), "{error:?}");
    assert!(diagnostic.message.contains("core::function"), "{error:?}");
}
