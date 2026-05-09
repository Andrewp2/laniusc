use std::time::{Duration, Instant};

mod common;

use common::sample_programs::load_sample_programs;
use laniusc::{
    compiler::{GpuCompiler, compile_source_to_wasm_with_gpu_codegen_using},
    gpu::device,
};

#[test]
fn sample_programs_compile_to_wasm_and_match_stdout_under_100ms() {
    common::require_node();

    pollster::block_on(async {
        let compiler = GpuCompiler::new_with_device(device::global())
            .await
            .expect("initialize reusable GPU compiler");
        compile_source_to_wasm_with_gpu_codegen_using("fn main() { return 0; }\n", &compiler)
            .await
            .expect("warm up reusable WASM compiler");

        let programs = load_sample_programs();

        for program in programs {
            let start = Instant::now();
            let wasm = compile_source_to_wasm_with_gpu_codegen_using(program.source(), &compiler)
                .await
                .unwrap_or_else(|err| {
                    panic!(
                        "{}: compile WASM from {}: {err}",
                        program.name(),
                        program.path().display()
                    )
                });
            let elapsed = start.elapsed();
            assert!(
                elapsed < Duration::from_millis(100),
                "{}: WASM compile took {elapsed:?}, expected under 100ms",
                program.name()
            );
            println!(
                "{}: wasm_compile_ms={:.3}",
                program.name(),
                elapsed.as_secs_f64() * 1000.0
            );

            let stdout = common::run_wasm_main_with_node(
                format!("{}: WASM sample", program.name()),
                program.name(),
                &wasm,
            );
            program.assert_stdout_eq("WASM", &stdout);
        }
    });
}
