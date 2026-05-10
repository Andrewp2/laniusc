mod common;

use laniusc::compiler::CompileError;

fn assert_gpu_type_check_ok(src: &str) {
    common::type_check_source_with_timeout(src).expect("source should pass GPU type checking");
}

fn assert_gpu_type_check_rejects(src: &str) {
    match common::type_check_source_with_timeout(src) {
        Ok(()) => panic!("source should fail GPU type checking"),
        Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type check error, got {other:?}"),
    }
}

#[test]
fn type_checker_accepts_struct_literals_members_and_field_assignment() {
    let src = r#"
struct Pair {
    left: i32,
    flag: bool,
}

fn main() {
    let pair: Pair = Pair { left: 7, flag: true };
    pair.left = 8;
    pair.flag = false;
    let left: i32 = pair.left;
    let flag: bool = pair.flag;
    if (flag) {
        return left;
    }
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_struct_function_parameters_and_returns() {
    let src = r#"
struct Pair {
    left: i32,
    flag: bool,
}

fn make_pair() -> Pair {
    return Pair { left: 7, flag: true };
}

fn get_left(pair: Pair) -> i32 {
    return pair.left;
}

fn main() {
    return get_left(make_pair());
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_extern_function_calls() {
    let src = r#"
extern "host" fn host_alloc(size: usize, align: usize) -> u32;
extern fn host_log_i32(value: i32);

fn main() {
    let ptr: u32 = host_alloc(16, 4);
    host_log_i32(ptr);
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_generic_declarations_and_annotations() {
    let src = r#"
struct Boxed<T> {
    value: T,
}

enum Maybe<T> {
    Some(T),
    None,
}

fn keep<T>(value: T) -> T {
    let copied: T = value;
    return copied;
}

fn keep_box(value: Boxed<i32>) -> Boxed<i32> {
    let copied: Boxed<i32> = value;
    return copied;
}

fn keep_maybe(value: Maybe<i32>) -> Maybe<i32> {
    let copied: Maybe<i32> = value;
    return copied;
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_const_generic_i32_array_parameters() {
    let src = r#"
fn first_i32<const N: usize>(values: [i32; N]) -> i32 {
    return values[0];
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    return first_i32(values);
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_enum_constructors_with_concrete_types() {
    let src = r#"
enum MaybeI32 {
    Some(i32),
    None,
}

fn make_value(value: i32) -> MaybeI32 {
    return Some(value);
}

fn choose(value: MaybeI32) -> MaybeI32 {
    return value;
}

fn main() {
    let value: MaybeI32 = make_value(7);
    let fallback: MaybeI32 = choose(value);
    let empty: MaybeI32 = None;
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_i32_slice_parameters_and_indexing() {
    let src = r#"
fn first(values: [i32]) -> i32 {
    return values[0];
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_rejects_core_type_mismatches_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
fn main() {
    let value: i32 = true;
    return value;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn main() {
    if (1) {
        return 1;
    }
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn main() {
    let values: [i32; 2] = [1, 2];
    return values[true];
}
"#,
    );
}

#[test]
fn type_checker_rejects_invalid_struct_usage_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
struct Pair {
    left: i32,
}

fn main() {
    let pair: Pair = Pair { left: true };
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
struct Pair {
    left: i32,
}

fn main() {
    let pair: Pair = Pair { right: 1 };
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn main() {
    let value: i32 = 1;
    return value.field;
}
"#,
    );
}
