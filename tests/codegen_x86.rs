mod common;

use laniusc::compiler::{
    CompileError,
    compile_source_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen_from_path,
};

#[test]
fn x86_compiler_route_stays_unwired_from_wasm_translation_prototype() {
    let compiler = include_str!("../src/compiler.rs");
    let gpu_x86 = include_str!("../src/codegen/gpu_x86.rs");
    let plan = include_str!("../docs/X86_64_GPU_BACKEND_PLAN.md");

    assert!(compiler.contains("gpu_x86_unavailable_error()"));
    assert!(!compiler.contains("codegen::gpu_x86"));
    assert!(!compiler.contains("record_x86_from_gpu_token_buffer"));
    assert!(!compiler.contains("x86_generator"));

    assert!(gpu_x86.contains("x86_from_wasm.spv"));
    assert!(gpu_x86.contains("wasm_functions.spv"));
    assert!(gpu_x86.contains("body_words"));
    assert!(gpu_x86.contains("functions_words"));

    assert!(plan.contains("Primitive helpers should not become \"native\""));
    assert!(plan.contains("feeding token-driven WASM buffers into `x86_from_wasm`"));
    assert!(plan.contains("direct HIR lowering"));
}

#[test]
fn x86_path_codegen_reports_missing_input_before_backend_unavailable() {
    let missing = common::temp_artifact_path("laniusc_missing_x86", "input", Some("lani"));
    if let Err(err) = std::fs::remove_file(&missing) {
        log::warn!(
            "failed to remove stale missing-input artifact {}: {err}",
            missing.display()
        );
    }

    let err = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(
        &missing,
    ))
    .expect_err("missing x86 input should fail while preparing source");

    let message = err.to_string();
    match err {
        CompileError::GpuFrontend(_) => {}
        other => panic!("expected GPU frontend read error, got {other:?}: {message}"),
    }
    assert!(
        message.contains("read") && message.contains(&missing.display().to_string()),
        "missing input error should name the unreadable path: {message}"
    );
    assert!(
        !message.contains("GPU x86_64 codegen is not currently available"),
        "missing input should not be reported as backend unavailability: {message}"
    );
}

#[test]
fn x86_source_codegen_reports_backend_unavailable_without_dispatch() {
    let err = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
        "fn main() {\n    return 0;\n}\n",
    ))
    .expect_err("x86 codegen should remain unavailable until the GPU backend is wired");

    let message = err.to_string();
    match err {
        CompileError::GpuCodegen(_) => {}
        other => panic!("expected GPU codegen unavailability, got {other:?}: {message}"),
    }
    assert!(
        message.contains("GPU x86_64 codegen is not currently available"),
        "unexpected x86 codegen error: {message}"
    );
    assert!(
        message.contains("CPU backend route has been removed"),
        "x86 unavailability must not imply a CPU fallback route: {message}"
    );
}

#[test]
fn x86_path_codegen_reads_existing_input_before_backend_unavailable() {
    let src_path = common::TempArtifact::new("laniusc_gpu_x86", "input", Some("lani"));
    src_path.write_str("fn main() {\n    return 0;\n}\n");

    let err = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(
        src_path.path(),
    ))
    .expect_err("x86 path codegen should read source before reporting backend unavailability");

    let message = err.to_string();
    match err {
        CompileError::GpuCodegen(_) => {}
        other => panic!("expected GPU codegen unavailability, got {other:?}: {message}"),
    }
    assert!(
        message.contains("GPU x86_64 codegen is not currently available"),
        "unexpected x86 codegen error: {message}"
    );
    assert!(
        message.contains("CPU backend route has been removed"),
        "x86 unavailability must not imply a CPU fallback route: {message}"
    );
}
