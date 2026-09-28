mod common;

use laniusc_compiler::compiler::{
    compile_source_pack_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen,
};

#[test]
fn unused_void_return_helper_does_not_break_native_emission() {
    let source = include_str!("fixtures/stdlib_foundation/repro_void_return.lani");
    let bytes = common::run_gpu_codegen_with_timeout("unused void return", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect("compile unused void-return helper");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("unused void return", "repro_void_return_unused", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_void_return_helper_exits_at_each_return() {
    let sources = [
        include_str!("fixtures/stdlib_foundation/repro_void_return_root/app/helper.lani"),
        include_str!("fixtures/stdlib_foundation/repro_void_return_root/app/main.lani"),
    ];
    let bytes = common::run_gpu_codegen_with_timeout("imported void return", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("compile imported void-return helper");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported void return",
            "repro_void_return_imported",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}
