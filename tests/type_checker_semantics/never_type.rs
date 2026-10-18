// The never type `!`: a call of a `-> !` function has type never, which is
// accepted wherever a type is expected; a match takes the type of its other
// arms; a body may end in such a call; a `-> !` function may fall off its end.

use super::{assert_gpu_type_check_ok, assert_gpu_type_check_pack_ok, assert_gpu_type_check_rejects};

const FAIL: &str = "fn fail() -> ! {\n    assert(false);\n}\n";

fn with_fail(body: &str) -> String {
    format!("{FAIL}{body}")
}

#[test]
fn type_checker_accepts_never_function_falling_off_its_end() {
    assert_gpu_type_check_ok(&with_fail(
        r#"
fn main() -> i32 {
    if (false) {
        fail();
    }
    return 0;
}
"#,
    ));
}

#[test]
fn type_checker_accepts_body_ending_in_never_call() {
    assert_gpu_type_check_ok(&with_fail(
        r#"
fn pick(flag: bool) -> i32 {
    if (flag) {
        return 1;
    }
    fail();
}

fn main() -> i32 {
    return pick(true) - 1;
}
"#,
    ));
}

#[test]
fn type_checker_accepts_never_match_arm_after_value_arm() {
    assert_gpu_type_check_ok(&with_fail(
        r#"
enum Opt { Some(i32), None }

fn unwrap(value: Opt) -> i32 {
    return match (value) { Some(inner) -> inner, None -> fail() };
}

fn main() -> i32 {
    return unwrap(Some(0));
}
"#,
    ));
}

#[test]
fn type_checker_accepts_never_match_arm_before_value_arm() {
    assert_gpu_type_check_ok(&with_fail(
        r#"
enum Opt { Some(i32), None }

fn unwrap(value: Opt) -> i32 {
    let inner: i32 = match (value) { None -> fail(), Some(inner) -> inner };
    return inner;
}

fn main() -> i32 {
    return unwrap(Some(0));
}
"#,
    ));
}

#[test]
fn type_checker_accepts_generic_unwrap_with_imported_panic_arm() {
    assert_gpu_type_check_pack_ok(&[
        r#"
module core::panic;

pub fn panic() -> ! {
    assert(false);
}
"#,
        r#"
module app::main;

import core::panic;
enum Opt<T> { Some(T), None }
fn unwrap<T>(value: Opt<T>) -> T {
    return match (value) { Some(inner) -> inner, None -> core::panic::panic() };
}
fn main() -> i32 {
    let a: Opt<i32> = Some(42);
    return unwrap(a) - 42;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_never_call_where_a_value_is_expected() {
    assert_gpu_type_check_ok(&with_fail(
        r#"
struct W { v: i32 }

fn take(value: i32) -> i32 {
    return value;
}

fn early() -> i32 {
    return fail();
}

fn main() -> i32 {
    if (false) {
        let x: i32 = fail();
        let w: W = W { v: fail() };
        let y: i32 = take(fail());
        return x + w.v + y + early();
    }
    return 0;
}
"#,
    ));
}

#[test]
fn type_checker_rejects_value_returned_from_never_function() {
    assert_gpu_type_check_rejects(
        r#"
fn fail() -> ! {
    return 1;
}

fn main() -> i32 {
    fail();
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_rejects_mismatched_value_arms_beside_never_arm() {
    assert_gpu_type_check_rejects(&with_fail(
        r#"
enum Pick { A, B, C }

fn choose(p: Pick) -> i32 {
    return match (p) { A -> 1, B -> fail(), C -> true };
}

fn main() -> i32 {
    return choose(A);
}
"#,
    ));
}

#[test]
fn type_checker_accepts_if_arms_ending_in_return_and_never_call() {
    assert_gpu_type_check_ok(&with_fail(
        r#"
fn pick(flag: bool) -> i32 {
    if (flag) {
        return 1;
    } else {
        fail();
    }
}

fn main() -> i32 {
    return pick(true) - 1;
}
"#,
    ));
}

#[test]
fn type_checker_rejects_never_call_in_only_one_arm() {
    assert_gpu_type_check_rejects(&with_fail(
        r#"
fn pick(flag: bool) -> i32 {
    if (flag) {
        fail();
    }
}

fn main() -> i32 {
    return pick(true);
}
"#,
    ));
}
