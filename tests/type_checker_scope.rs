use laniusc::compiler::{CompileError, compile_source_to_wasm_with_gpu_codegen};

#[test]
fn type_checker_rejects_let_initializer_self_reference() {
    let src = r#"
fn main() {
    let x = x;
    return 0;
}
"#;

    let err = pollster::block_on(compile_source_to_wasm_with_gpu_codegen(src))
        .expect_err("self-referential let initializer should fail type checking");

    match err {
        CompileError::GpuTypeCheck(message) => {
            assert!(
                message.contains("UnresolvedIdent"),
                "expected unresolved identifier error, got {message}"
            );
        }
        other => panic!("expected GPU type check error, got {other:?}"),
    }
}
