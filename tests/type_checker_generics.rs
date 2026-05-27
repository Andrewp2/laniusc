mod common;

fn assert_gpu_type_check_ok(src: &str) {
    common::type_check_source_with_timeout(src).expect("source should pass GPU type checking");
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
