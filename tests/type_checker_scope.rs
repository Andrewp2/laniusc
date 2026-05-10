mod common;

use laniusc::compiler::CompileError;

fn assert_gpu_type_check_error(src: &str, code: &str) {
    let err = common::type_check_source_with_timeout(src)
        .expect_err("source should fail GPU type checking");

    match err {
        CompileError::GpuTypeCheck(message) => {
            assert!(
                message.contains(code),
                "expected {code} GPU type check error, got {message}"
            );
        }
        other => panic!("expected GPU type check error, got {other:?}"),
    }
}

fn assert_gpu_compile_ok(src: &str) {
    common::type_check_source_with_timeout(src).expect("source should pass GPU type checking");
}

#[test]
fn type_checker_rejects_let_initializer_self_reference() {
    let src = r#"
fn main() {
    let x = x;
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "UnresolvedIdent");
}

#[test]
fn type_checker_rejects_typed_array_let_initializer_self_reference() {
    let src = r#"
fn main() {
    let values: [i32; 2] = values;
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "UnresolvedIdent");
}

#[test]
fn type_checker_rejects_use_before_declaration() {
    let src = r#"
fn main() {
    print(later);
    let later: i32 = 1;
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "UnresolvedIdent");
}

#[test]
fn type_checker_rejects_inner_block_declaration_leak() {
    let src = r#"
fn main() {
    if (1 == 1) {
        let hidden: i32 = 1;
        print(hidden);
    }
    print(hidden);
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "UnresolvedIdent");
}

#[test]
fn type_checker_keeps_shadowing_block_local() {
    let src = r#"
fn main() {
    let x: i32 = 1;
    if (1 == 1) {
        print(x);
        let x: bool = 1 < 2;
        if (x) {
            print(2);
        }
    }
    print(x);
    return 0;
}
"#;

    assert_gpu_compile_ok(src);
}

#[test]
fn type_checker_keeps_parameters_visible_only_in_their_function() {
    let accepts = r#"
fn echo(value: i32) -> i32 {
    return value;
}

fn main() {
    print(echo(3));
    return 0;
}
"#;

    let rejects = r#"
fn helper(hidden: i32) -> i32 {
    let local: i32 = hidden;
    return local;
}

fn main() {
    print(hidden);
    return 0;
}
"#;

    assert_gpu_compile_ok(accepts);
    assert_gpu_type_check_error(rejects, "UnresolvedIdent");
}
