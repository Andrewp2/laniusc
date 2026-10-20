// The never type `!` (a return type only). A call of a `-> !` function has
// type never, which fits any expected type; a match takes the type of its
// other arms; a body may end in such a call. A `-> !` function must not
// return: it may not contain a `return` of a value, and every path through its
// body must end in a diverging call (another `-> !` call or `assert(false)`).

use super::{
    assert_gpu_type_check_diagnostic, assert_gpu_type_check_ok, assert_gpu_type_check_pack_ok,
    assert_gpu_type_check_rejects,
};

const FAIL: &str = "fn fail() -> ! {\n    assert(false);\n}\n";

fn with_fail(body: &str) -> String {
    format!("{FAIL}{body}")
}

#[test]
fn type_checker_accepts_never_functions_whose_every_path_diverges() {
    assert_gpu_type_check_ok(&with_fail(
        r#"
fn die(flag: bool) -> ! {
    if (flag) {
        fail();
    } else {
        assert(false);
    }
}

fn main() -> i32 {
    if (false) {
        die(true);
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
        include_str!("../../stdlib/core/panic.lani"),
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
fn type_checker_rejects_return_from_never_function() {
    assert_gpu_type_check_diagnostic(
        r#"
fn fail(flag: bool) -> ! {
    if (flag) {
        return 1;
    }
    assert(false);
}

fn main() -> i32 {
    fail(true);
    return 0;
}
"#,
        "LNC0006",
        &[":4:9", "a function returning `!` cannot return"],
    );
}

#[test]
fn type_checker_rejects_never_function_that_can_reach_its_end() {
    assert_gpu_type_check_diagnostic(
        r#"
fn fail(flag: bool) -> ! {
    if (flag) {
        assert(false);
    }
    assert(true);
}

fn main() -> i32 {
    fail(true);
    return 0;
}
"#,
        "LNC0006",
        &[":2:4", "the end of its body can be reached"],
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
