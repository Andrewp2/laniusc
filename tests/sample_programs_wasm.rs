use std::{
    fs,
    process::Command,
    time::{Duration, Instant},
};

mod common;

use common::sample_programs::{SampleProgram, load_sample_programs};
use laniusc::{
    compiler::{GpuCompiler, compile_source_to_wasm_with_gpu_codegen_using},
    gpu::device,
};

#[test]
fn sample_programs_compile_to_wasm_and_match_stdout_under_100ms() {
    Command::new("node")
        .arg("--version")
        .output()
        .expect("node is required to execute sample WASM modules");

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

            let stdout = run_wasm_with_node(&program, &wasm);
            program.assert_stdout_eq("WASM", &stdout);
        }
    });
}

fn run_wasm_with_node(program: &SampleProgram, wasm: &[u8]) -> String {
    let wasm_path = common::temp_artifact_path("laniusc_sample_wasm", program.name(), Some("wasm"));
    fs::write(&wasm_path, wasm).unwrap_or_else(|err| {
        panic!(
            "{}: write temporary WASM {}: {err}",
            program.name(),
            wasm_path.display()
        )
    });

    let script = r#"
const fs = require('fs');
(async () => {
  let stdout = '';
  const imports = {
    env: {
      print_i64(value) {
        stdout += value.toString() + '\n';
      }
    }
  };
  const module = await WebAssembly.instantiate(fs.readFileSync(process.argv[1]), imports);
  module.instance.exports.main();
  process.stdout.write(stdout);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
"#;
    let output = Command::new("node")
        .arg("-e")
        .arg(script)
        .arg(&wasm_path)
        .output()
        .unwrap_or_else(|err| {
            panic!(
                "{}: run node for {}: {err}",
                program.name(),
                wasm_path.display()
            )
        });
    let _ = fs::remove_file(&wasm_path);
    assert!(
        output.status.success(),
        "{}: node failed for {}:\nstdout:\n{}\nstderr:\n{}",
        program.name(),
        wasm_path.display(),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout)
        .unwrap_or_else(|err| panic!("{}: node stdout utf8: {err}", program.name()))
}
