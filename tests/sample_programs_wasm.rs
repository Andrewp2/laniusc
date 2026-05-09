use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
    time::{Duration, Instant},
};

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

        let programs = sample_programs();

        for program in programs {
            let name = program
                .file_stem()
                .and_then(|stem| stem.to_str())
                .expect("sample program file stem");
            let src = fs::read_to_string(&program)
                .unwrap_or_else(|err| panic!("{name}: read {}: {err}", program.display()));
            let expected_path = program.with_extension("stdout");
            let expected = fs::read_to_string(&expected_path)
                .unwrap_or_else(|err| panic!("{name}: read {}: {err}", expected_path.display()));

            let start = Instant::now();
            let wasm = compile_source_to_wasm_with_gpu_codegen_using(&src, &compiler)
                .await
                .unwrap_or_else(|err| panic!("{name}: compile WASM: {err}"));
            let elapsed = start.elapsed();
            assert!(
                elapsed < Duration::from_millis(100),
                "{name}: WASM compile took {elapsed:?}, expected under 100ms"
            );
            println!(
                "{name}: wasm_compile_ms={:.3}",
                elapsed.as_secs_f64() * 1000.0
            );

            let stdout = run_wasm_with_node(name, &wasm);
            assert_eq!(stdout, expected, "{name}: WASM stdout mismatch");
        }
    });
}

fn sample_programs() -> Vec<PathBuf> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("sample_programs");
    let mut programs = Vec::new();
    let mut expected_outputs = Vec::new();
    for entry in fs::read_dir(&root)
        .unwrap_or_else(|err| panic!("read sample_programs dir {}: {err}", root.display()))
    {
        let path = entry
            .unwrap_or_else(|err| panic!("read sample_programs entry: {err}"))
            .path();
        match path.extension().and_then(|ext| ext.to_str()) {
            Some("lani") => programs.push(path),
            Some("stdout") => expected_outputs.push(path),
            _ => {}
        }
    }
    programs.sort();
    expected_outputs.sort();
    assert!(
        !programs.is_empty(),
        "expected at least one sample program in {}",
        root.display()
    );

    let missing_stdout = programs
        .iter()
        .filter(|program| !program.with_extension("stdout").is_file())
        .map(sample_file_name)
        .collect::<Vec<_>>();
    assert!(
        missing_stdout.is_empty(),
        "sample programs missing .stdout files: {}",
        missing_stdout.join(", ")
    );

    let orphan_stdout = expected_outputs
        .iter()
        .filter(|expected| !expected.with_extension("lani").is_file())
        .map(sample_file_name)
        .collect::<Vec<_>>();
    assert!(
        orphan_stdout.is_empty(),
        "sample stdout files missing .lani programs: {}",
        orphan_stdout.join(", ")
    );

    programs
}

fn sample_file_name(path: &PathBuf) -> String {
    path.file_name()
        .and_then(|name| name.to_str())
        .map(str::to_owned)
        .unwrap_or_else(|| path.display().to_string())
}

fn run_wasm_with_node(name: &str, wasm: &[u8]) -> String {
    let wasm_path = std::env::temp_dir().join(format!(
        "laniusc_sample_wasm_{name}_{}_{}.wasm",
        std::process::id(),
        unique_suffix()
    ));
    fs::write(&wasm_path, wasm).unwrap_or_else(|err| {
        panic!(
            "{name}: write temporary WASM {}: {err}",
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
        .unwrap_or_else(|err| panic!("{name}: run node: {err}"));
    let _ = fs::remove_file(&wasm_path);
    assert!(
        output.status.success(),
        "{name}: node failed:\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).unwrap_or_else(|err| panic!("{name}: stdout utf8: {err}"))
}

fn unique_suffix() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos()
}
