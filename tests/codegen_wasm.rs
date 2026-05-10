use std::{fs, process::Command};

mod common;

#[test]
#[ignore = "GPU WASM codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_emits_wasm_for_top_level_lets() {
    let src = "let x = 1;\nlet y = 2;\n";
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "GPU WASM codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_cli_emits_wasm_file() {
    let src_path = common::TempArtifact::new("laniusc_gpu_wasm", "cli_source", Some("lani"));
    let out_path = common::TempArtifact::new("laniusc_gpu_wasm", "cli_output", Some("wasm"));
    src_path.write_str("let x = 1;\n");

    let bin = option_env!("CARGO_BIN_EXE_laniusc").unwrap_or("target/debug/laniusc");
    let mut command = Command::new(bin);
    command
        .env("LANIUS_READBACK", "0")
        .env("PERF_ONE_READBACK", "0")
        .arg("--emit")
        .arg("wasm")
        .arg(src_path.path())
        .arg("-o")
        .arg(out_path.path());
    let output = common::command_output_with_timeout("laniusc --emit wasm", &mut command);

    common::assert_command_success("laniusc --emit wasm", &output);
    let wasm = fs::read(out_path.path()).expect("read emitted WASM");
    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "GPU WASM codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_rejects_function_bodies_without_cpu_backend_route() {
    let src = "fn main() {\n    return 0;\n}\n";
    let err = common::compile_source_to_wasm_with_timeout(src)
        .expect_err("function-body WASM lowering should fail until the GPU path supports it");
    let message = err.to_string();
    assert!(
        message.contains("GPU WASM emitter produced"),
        "unexpected function-body rejection: {message}"
    );
}

fn assert_lanius_wasm(bytes: &[u8]) {
    assert!(
        bytes.len() >= 37,
        "WASM output too small: {} bytes",
        bytes.len()
    );
    assert_eq!(
        &bytes[0..8],
        &[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
    );
    assert!(contains_bytes(bytes, b"\x03env\x09print_i64"));
    assert!(contains_bytes(bytes, b"\x04main\x00"));
}

fn run_wasm_main_if_node_available(wasm: &[u8], expected_stdout: &str) {
    if !common::node_available() {
        return;
    }
    let stdout = common::run_wasm_main_with_node("codegen WASM check", "codegen_wasm", wasm);
    assert_eq!(
        stdout, expected_stdout,
        "codegen WASM stdout mismatch\nexpected:\n{expected_stdout:?}\nactual:\n{stdout:?}"
    );
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    haystack
        .windows(needle.len())
        .any(|candidate| candidate == needle)
}
