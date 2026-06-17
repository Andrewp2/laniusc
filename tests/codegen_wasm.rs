mod common;

use laniusc_compiler::compiler::CompileError;

#[test]
fn wasm_rejects_scalar_programs_with_stable_backend_diagnostic() {
    let err = common::compile_source_to_wasm_with_timeout("fn main() { return 7; }\n")
        .expect_err("retired WASM byte emitter should fail closed for scalar source");

    assert_wasm_backend_boundary(err);
}

#[test]
fn wasm_rejects_for_loop_with_stable_backend_diagnostic() {
    let err = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let values: [i32; 3] = [1, 2, 3];
    let total: i32 = 0;
    for value in values {
        total += value;
    }
    return total;
}
"#,
    )
    .expect_err("WASM should fail closed for loops until WASM lowering consumes for records");

    assert_wasm_backend_boundary(err);
}

fn assert_wasm_backend_boundary(err: CompileError) {
    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0036",
                "WASM backend rejection should use a stable diagnostic: {message}"
            );
            assert!(
                diagnostic.message.contains("for loop")
                    || diagnostic.message.contains("WASM")
                    || diagnostic.message.contains("unsupported"),
                "diagnostic should identify the WASM backend boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("WASM backend diagnostic should include a primary label");
            assert!(
                label.line > 0,
                "diagnostic should be source-spanned: {message}"
            );
            assert!(
                label.column > 0,
                "diagnostic should include a source column: {message}"
            );
            assert!(
                label.length > 0,
                "diagnostic span should be non-empty: {message}"
            );
        }
        other => panic!("expected stable WASM backend diagnostic, got {other:?}"),
    }
}
