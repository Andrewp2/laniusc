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

#[test]
fn transitive_host_exit_preserves_native_entrypoint() {
    let sources = [
        include_str!("fixtures/stdlib_foundation/repro_transitive_host_root/std/process.lani"),
        include_str!("fixtures/stdlib_foundation/repro_transitive_host_root/test/probe.lani"),
        include_str!("fixtures/stdlib_foundation/repro_transitive_host_import.lani"),
    ];
    let bytes = common::run_gpu_codegen_with_timeout("transitive host exit", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("compile transitive host exit");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "transitive host exit",
            "repro_transitive_host_import",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn directly_imported_host_exit_runs_on_failure() {
    let sources = [
        include_str!(
            "fixtures/stdlib_foundation/repro_transitive_host_root/test/probe_direct_exit.lani"
        ),
        "module app::main;\nimport test::probe_direct_exit;\nfn main() -> i32 {\n    test::probe_direct_exit::require(false);\n    return 0;\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout("direct imported host exit", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("compile directly imported host exit");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "direct imported host exit",
            "repro_direct_host_exit",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(7), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}
