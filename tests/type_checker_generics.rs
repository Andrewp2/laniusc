mod common;

use laniusc::compiler::CompileError;

fn assert_gpu_type_check_ok(src: &str) {
    common::type_check_source_with_timeout(src).expect("source should pass GPU type checking");
}

fn assert_gpu_type_check_rejects_with_code(src: &str, code: &str) {
    match common::type_check_source_with_timeout(src) {
        Ok(()) => panic!("source should fail GPU type checking with {code}"),
        Err(CompileError::GpuTypeCheck(message)) => assert!(
            message.contains(code),
            "expected GPU type check error containing {code}, got {message}"
        ),
        Err(other) => panic!("expected GPU type check error, got {other:?}"),
    }
}

#[test]
fn type_checker_accepts_nested_direct_generic_function_calls() {
    assert_gpu_type_check_ok(
        r#"
fn keep<T>(value: T) -> T {
    return value;
}

fn main() {
    let value: i32 = keep(keep(7));
    let flag: bool = keep(keep(true));
    if (flag) {
        return value;
    }
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_nested_generic_forwarding_through_helpers() {
    assert_gpu_type_check_ok(
        r#"
fn keep<T>(value: T) -> T {
    return value;
}

fn forward<T>(value: T) -> T {
    return keep(keep(value));
}

fn forward_again<T>(value: T) -> T {
    return keep(forward(value));
}

fn main() {
    let value: i32 = forward_again(7);
    return value;
}
"#,
    );
}

#[test]
fn type_checker_rejects_repeated_generic_conflict_from_nested_calls() {
    assert_gpu_type_check_rejects_with_code(
        r#"
fn keep<T>(value: T) -> T {
    return value;
}

fn choose<T>(left: T, right: T) -> T {
    return left;
}

fn main() {
    let value: i32 = choose(keep(1), keep(true));
    return value;
}
"#,
        "AssignMismatch",
    );

    assert_gpu_type_check_rejects_with_code(
        r#"
fn keep<T>(value: T) -> T {
    return value;
}

fn choose<T>(left: T, right: T) -> T {
    return left;
}

fn main() {
    choose(keep(1), keep(true));
    return 0;
}
"#,
        "AssignMismatch",
    );
}
