use laniusc::compiler::{CompileError, compile_source_to_wasm_with_gpu_codegen};

fn assert_gpu_type_check_error(src: &str, expected: &str) {
    let err = pollster::block_on(compile_source_to_wasm_with_gpu_codegen(src))
        .expect_err("source should fail GPU type checking");

    match err {
        CompileError::GpuTypeCheck(message) => {
            assert!(
                message.contains(expected),
                "expected GPU type check error containing {expected:?}, got {message:?}"
            );
        }
        other => panic!("expected GPU type check error, got {other:?}"),
    }
}

#[test]
fn type_checker_rejects_plain_assignment_type_mismatch() {
    let src = r#"
fn main() {
    let flag: bool = 1 < 2;
    let count: i32 = 1;
    flag = count;
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch (515)");
}

#[test]
fn type_checker_rejects_bool_compound_assignment() {
    let src = r#"
fn main() {
    let flag: bool = 1 < 2;
    flag += 2 > 1;
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch (514)");
}

#[test]
fn type_checker_rejects_float_integer_compound_assignment() {
    let src = r#"
fn main() {
    let value: f32 = 1.0;
    value %= 1;
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch (1283)");
}

#[test]
fn type_checker_rejects_return_type_mismatch() {
    let src = r#"
fn truth() -> bool {
    return 1;
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "ReturnMismatch (515)");
}

#[test]
fn type_checker_rejects_integer_condition() {
    let src = r#"
fn main() {
    let count: i32 = 1;
    if (count) {
        print(1);
    }
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "ConditionType (3)");
}

#[test]
fn type_checker_rejects_array_condition() {
    let src = r#"
fn main() {
    let values: [i32; 2] = [1, 2];
    if (values) {
        print(1);
    }
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "ConditionType (131)");
}
