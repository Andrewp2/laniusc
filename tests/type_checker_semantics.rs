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
fn type_checker_rejects_bool_literal_in_integer_expression() {
    let src = r#"
fn main() {
    let value: i32 = true + 1;
    return value;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch");
}

#[test]
fn type_checker_rejects_integer_assert_argument() {
    let src = r#"
fn main() {
    assert(1);
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch");
}

#[test]
fn type_checker_rejects_const_initializer_type_mismatch() {
    let src = r#"
const LIMIT: i32 = true;

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch");
}

#[test]
fn type_checker_rejects_assignment_to_const() {
    let src = r#"
const LIMIT: i32 = 7;

fn main() {
    LIMIT = 8;
    return LIMIT;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch");
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

#[test]
fn type_checker_rejects_call_argument_count_mismatch() {
    let src = r#"
fn add(left: i32, right: i32) -> i32 {
    return left;
}

fn main() {
    print(add(1));
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "CallMismatch (513)");
}

#[test]
fn type_checker_rejects_call_argument_type_mismatch() {
    let src = r#"
fn as_int(value: i32) -> i32 {
    return value;
}

fn main() {
    let flag: bool = 1 < 2;
    print(as_int(flag));
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch (770)");
}

#[test]
fn type_checker_rejects_calling_non_function_value() {
    let src = r#"
fn main() {
    let value: i32 = 1;
    value();
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "CallMismatch (3)");
}

#[test]
fn type_checker_rejects_function_name_as_value() {
    let src = r#"
fn helper() -> i32 {
    return 1;
}

fn main() {
    let value: i32 = helper;
    return value;
}
"#;

    assert_gpu_type_check_error(src, "CallMismatch (0)");
}

#[test]
fn type_checker_rejects_non_integer_array_index() {
    let src = r#"
fn main() {
    let values: [i32; 2] = [1, 2];
    let flag: bool = 1 < 2;
    let value: i32 = values[flag];
    return value;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch (770)");
}

#[test]
fn type_checker_rejects_indexing_non_array_value() {
    let src = r#"
fn main() {
    let value: i32 = 1;
    let result: i32 = value[0];
    return result;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch (3)");
}

#[test]
fn type_checker_rejects_array_element_assignment_mismatch() {
    let src = r#"
fn main() {
    let values: [i32; 2] = [1, 2];
    let flag: bool = 1 < 2;
    values[0] = flag;
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch (770)");
}

#[test]
fn type_checker_rejects_inferred_array_literal_element_mismatch() {
    let src = r#"
fn main() {
    let first: i32 = 1;
    let values = [first, 1 < 2];
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch (770)");
}

#[test]
fn type_checker_keeps_nested_call_commas_inside_argument() {
    let src = r#"
fn pair(left: i32, right: i32) -> i32 {
    return left;
}

fn takes_one(value: i32) -> i32 {
    return value;
}

fn main() {
    let flag: bool = takes_one(pair(1, 2));
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch (515)");
}
