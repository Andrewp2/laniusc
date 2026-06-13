mod common;

use laniusc::compiler::CompileError;

fn assert_gpu_type_check_ok(src: &str) {
    common::type_check_source_with_timeout(src).expect("source should pass GPU type checking");
}

fn assert_gpu_type_check_pack_rejects(sources: &[&str]) {
    match common::type_check_source_pack_with_timeout(sources) {
        Ok(()) => panic!("source pack should fail GPU type checking"),
        Err(CompileError::Diagnostic(_)) => {}
        Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type check error, got {other:?}"),
    }
}

fn assert_gpu_type_check_pack_ok(sources: &[&str]) {
    common::type_check_source_pack_with_timeout(sources)
        .expect("source pack should pass GPU type checking");
}

fn assert_gpu_type_check_pack_diagnostic(
    sources: &[&str],
    expected_code: &str,
    expected_fragments: &[&str],
) {
    let err = common::type_check_source_pack_with_timeout(sources)
        .expect_err("source pack should fail GPU type checking");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            let rendered = diagnostic.render();
            assert_eq!(
                diagnostic.code, expected_code,
                "unexpected diagnostic code:\n{rendered}"
            );
            for fragment in expected_fragments {
                assert!(
                    rendered.contains(fragment),
                    "diagnostic missing fragment {fragment:?}:\n{rendered}"
                );
            }
        }
        other => panic!("expected diagnostic {expected_code}, got {other:?}"),
    }
}

fn assert_gpu_type_check_diagnostic(src: &str, expected_code: &str, expected_fragments: &[&str]) {
    let err = common::type_check_source_with_timeout(src)
        .expect_err("source should fail GPU type checking");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            let rendered = diagnostic.render();
            assert_eq!(
                diagnostic.code, expected_code,
                "unexpected diagnostic code:\n{rendered}"
            );
            for fragment in expected_fragments {
                assert!(
                    rendered.contains(fragment),
                    "diagnostic missing fragment {fragment:?}:\n{rendered}"
                );
            }
        }
        other => panic!("expected diagnostic {expected_code}, got {other:?}"),
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
fn type_checker_enforces_nominal_generic_argument_consistency_per_call_site() {
    assert_gpu_type_check_ok(
        r#"
enum Option<T> {
    Some(T),
    None,
}

fn score<T>(value: Option<T>, fallback: T) -> i32 {
    return 1;
}

fn main() {
    let number: Option<i32> = Some(1);
    let value: i32 = score(number, 2);
    return value;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
enum Option<T> {
    Some(T),
    None,
}

fn score<T>(value: Option<T>, fallback: T) -> i32 {
    return 1;
}

fn main() {
    let flag: Option<bool> = Some(true);
    let value: i32 = score(flag, 2);
    return value;
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "let value: i32 = score(flag, 2);",
            "value type is i32 but this context expects generic parameter 0",
        ],
    );
}

#[test]
fn type_checker_accepts_nested_generic_instance_return_consistency_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
enum Option<T> {
    Some(T),
    None,
}

fn wrap<T>(value: T) -> Option<T> {
    return Some(value);
}

fn score<T>(value: Option<T>, fallback: T) -> i32 {
    return 1;
}

fn main() {
    let value: i32 = score(wrap(1), 0);
    return value;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
enum Option<T> {
    Some(T),
    None,
}

fn wrap<T>(value: T) -> Option<T> {
    return Some(value);
}

fn score<T>(value: Option<T>, fallback: T) -> i32 {
    return 1;
}

fn main() {
    let value: i32 = score(wrap(true), 0);
    return value;
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "let value: i32 = score(wrap(true), 0);",
            "value type is i32 but this context expects generic parameter 0",
        ],
    );
}

#[test]
fn type_checker_infers_direct_generic_returns_from_nominal_instance_arguments_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
struct Boxed<T> {
    value: T,
}

fn unbox<T>(value: Boxed<T>) -> T {
    return value.value;
}

fn main() {
    let number: Boxed<i32> = Boxed { value: 7 };
    let value: i32 = unbox(number);
    return value;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

fn unbox<T>(value: Boxed<T>) -> T {
    return value.value;
}

fn main() {
    let flag: Boxed<bool> = Boxed { value: true };
    let value: i32 = unbox(flag);
    return value;
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "let value: i32 = unbox(flag);",
            "value type is bool",
        ],
    );
}

#[test]
fn type_checker_rejects_concrete_generic_instance_parameter_mismatch() {
    assert_gpu_type_check_ok(
        r#"
enum Pair<T> {
    Left(T),
    Right(T),
}

fn accept_i32(value: Pair<i32>) -> i32 {
    return 1;
}

fn make_i32() -> Pair<i32> {
    return Left(8);
}

fn main() {
    let number: Pair<i32> = Left(7);
    let value: i32 = accept_i32(number);
    let from_call: i32 = accept_i32(make_i32());
    return value + from_call;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
enum Pair<T> {
    Left(T),
    Right(T),
}

fn accept_i32(value: Pair<i32>) -> i32 {
    return 1;
}

fn make_bool() -> Pair<bool> {
    return Left(true);
}

fn main() {
    let value: i32 = accept_i32(make_bool());
    return value;
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "let value: i32 = accept_i32(make_bool());",
        ],
    );
}

#[test]
fn type_checker_rejects_repeated_generic_instance_slot_mismatch_per_argument() {
    assert_gpu_type_check_ok(
        r#"
enum Pair<Left, Right> {
    Both(Left, Right),
}

fn accept_same<T>(value: Pair<T, T>) -> i32 {
    return 1;
}

fn make_same() -> Pair<i32, i32> {
    return Both(1, 2);
}

fn main() {
    let value: Pair<i32, i32> = Both(3, 4);
    let named: i32 = accept_same(value);
    let returned: i32 = accept_same(make_same());
    return named + returned;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
enum Pair<Left, Right> {
    Both(Left, Right),
}

fn accept_same<T>(value: Pair<T, T>) -> i32 {
    return 1;
}

fn make_mixed() -> Pair<i32, bool> {
    return Both(1, true);
}

fn main() {
    let value: i32 = accept_same(make_mixed());
    return value;
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "let value: i32 = accept_same(make_mixed());",
        ],
    );
}

#[test]
fn type_checker_rejects_nested_generic_instance_parameters_without_partial_outer_match() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

struct Maybe<T> {
    value: T,
}

fn take_nested(value: Maybe<Boxed<i32>>) -> i32 {
    return 0;
}

fn main() {
    let value: i32 = take_nested(Maybe { value: Boxed { value: 7 } });
    return value;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "let value: i32 = take_nested(Maybe { value: Boxed { value: 7 } });",
            "the compiler rejects it rather than matching only the visible top-level type",
        ],
    );
}

#[test]
fn type_checker_rejects_unknown_generic_instance_argument_slot_on_gpu() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}

pub fn flag() -> Maybe<bool> {
    return Some(true);
}
"#,
        r#"
module app::main;

fn unwrap_or<T>(value: core::maybe::Maybe<T>, fallback: T) -> T {
    return fallback;
}

fn main() {
    let value: i32 = unwrap_or(core::maybe::flag(), 0);
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_enforces_repeated_generic_parameter_consistency_per_call_site() {
    assert_gpu_type_check_ok(
        r#"
fn choose<T>(left: T, right: T) -> T {
    return left;
}

fn main() {
    let number: i32 = choose(1, 2);
    let flag: bool = choose(true, false);
    if (flag) {
        return number;
    }
    return 0;
}
"#,
    );

    assert_gpu_type_check_pack_diagnostic(
        &[r#"
module app;

fn choose<T>(left: T, right: T) -> T {
    return left;
}

fn main() {
    let number: i32 = choose(1, false);
    return number;
}
"#],
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "let number: i32 = choose(1, false);",
            "value type is bool but this context expects generic parameter 0",
        ],
    );
}

#[test]
fn type_checker_substitutes_scalar_alias_arguments_per_generic_call_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
type Count = i32;

fn choose<T>(left: T, right: T) -> T {
    return left;
}

fn main() {
    let count: Count = 1;
    let value: i32 = choose(count, 2);
    let copied: Count = choose(3, count);
    return value + copied;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
type Flag = bool;

fn choose<T>(left: T, right: T) -> T {
    return left;
}

fn main() {
    let flag: Flag = false;
    let value: i32 = choose(flag, 2);
    return value;
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "let value: i32 = choose(flag, 2);",
        ],
    );
}

#[test]
fn type_checker_qualified_generic_calls_check_repeated_parameters_per_call_site() {
    assert_gpu_type_check_pack_ok(&[
        r#"
module core::choice;

pub fn choose<T>(left: T, right: T) -> T {
    return left;
}
"#,
        r#"
module app;

fn main() {
    let number: i32 = core::choice::choose(1, 2);
    let flag: bool = core::choice::choose(true, false);
    if (flag) {
        return number;
    }
    return 0;
}
"#,
    ]);

    assert_gpu_type_check_pack_diagnostic(
        &[
            r#"
module core::choice;

pub fn choose<T>(left: T, right: T) -> T {
    return left;
}
"#,
            r#"
module app;

fn main() {
    let value: i32 = core::choice::choose(1, false);
    return value;
}
"#,
        ],
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "let value: i32 = core::choice::choose(1, false);",
            "value type is i32, which is not accepted here",
        ],
    );
}

#[test]
fn type_checker_qualified_generic_calls_infer_return_from_nonzero_parameter_slot() {
    assert_gpu_type_check_pack_ok(&[
        r#"
module core::pair;

pub fn select_right<T, U>(left: T, right: U) -> U {
    return right;
}
"#,
        r#"
module app;

fn main() {
    let flag: bool = core::pair::select_right(1, true);
    let number: i32 = core::pair::select_right(false, 7);
    if (flag) {
        return number;
    }
    return 0;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::pair;

pub fn select_right<T, U>(left: T, right: U) -> U {
    return right;
}
"#,
        r#"
module app;

fn main() {
    let number: i32 = core::pair::select_right(1, true);
    return number;
}
"#,
    ]);
}

#[test]
fn type_checker_source_pack_generic_forwarding_preserves_qualified_return_substitution() {
    assert_gpu_type_check_pack_ok(&[
        r#"
module core::forward;

pub fn keep<T>(value: T) -> T {
    return value;
}

pub fn forward<T>(value: T) -> T {
    return keep(keep(value));
}

pub fn select_forwarded_right<T, U>(left: T, right: U) -> U {
    return forward(right);
}
"#,
        r#"
module app;

fn main() {
    let number: i32 = core::forward::forward(core::forward::keep(7));
    let flag: bool = core::forward::select_forwarded_right(number, true);
    if (flag) {
        return number;
    }
    return 0;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::forward;

pub fn keep<T>(value: T) -> T {
    return value;
}

pub fn forward<T>(value: T) -> T {
    return keep(keep(value));
}

pub fn select_forwarded_right<T, U>(left: T, right: U) -> U {
    return forward(right);
}
"#,
        r#"
module app;

fn main() {
    let number: i32 = core::forward::select_forwarded_right(1, true);
    return number;
}
"#,
    ]);
}

#[test]
fn type_checker_source_pack_qualified_generic_returns_are_per_declaration() {
    assert_gpu_type_check_pack_ok(&[
        r#"
module core::numbers;

pub fn keep<T>(value: T) -> T {
    return value;
}
"#,
        r#"
module core::flags;

pub fn keep<T>(value: T) -> T {
    return value;
}
"#,
        r#"
module app;

import core::numbers;
import core::flags;

fn main() {
    let number: i32 = core::numbers::keep(7);
    let flag: bool = core::flags::keep(true);
    if (flag) {
        return number;
    }
    return 0;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::numbers;

pub fn keep<T>(value: T) -> T {
    return value;
}
"#,
        r#"
module core::flags;

pub fn keep<T>(value: T) -> T {
    return value;
}
"#,
        r#"
module app;

import core::numbers;
import core::flags;

fn main() {
    let number: i32 = core::flags::keep(true);
    return number;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_uninferred_direct_generic_return_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
fn make<T>() -> T {
    return make();
}

fn main() {
    make();
    return 0;
}
"#,
        "LNC0006",
        &["error[LNC0006]: type mismatch", "make();"],
    );
}

#[test]
fn type_checker_rejects_uninferred_direct_generic_parameters_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
fn ignore_extra<T, U>(value: T) -> i32 {
    return 0;
}

fn main() {
    let value: i32 = ignore_extra(1);
    return value;
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "let value: i32 = ignore_extra(1);",
            "expected generic parameter 1, found unknown type",
        ],
    );
}

#[test]
fn type_checker_rejects_uninferred_qualified_generic_parameters_on_gpu() {
    assert_gpu_type_check_pack_diagnostic(
        &[
            r#"
module core::helpers;

pub fn ignore_extra<T, U>(value: T) -> i32 {
    return 0;
}
"#,
            r#"
module app;

fn main() {
    let value: i32 = core::helpers::ignore_extra(1);
    return value;
}
"#,
        ],
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "let value: i32 = core::helpers::ignore_extra(1);",
            "expected generic parameter 1, found unknown type",
        ],
    );
}

#[test]
fn type_checker_rejects_generic_calls_beyond_gpu_argument_width_before_substitution() {
    assert_gpu_type_check_diagnostic(
        r#"
fn choose_first<T>(first: T, second: T, third: T, fourth: T, fifth: T) -> T {
    return first;
}

fn main() {
    let value: i32 = choose_first(1, 2, 3, 4, true);
    return value;
}
"#,
        "LNC0027",
        &[
            "call resolution failed",
            "no supported function or method signature matches this receiver and argument list",
        ],
    );
}

#[test]
fn type_checker_rejects_qualified_generic_calls_beyond_gpu_argument_width_before_substitution() {
    assert_gpu_type_check_pack_diagnostic(
        &[
            r#"
module core::wide;

pub fn choose_first<T>(first: T, second: T, third: T, fourth: T, fifth: T) -> T {
    return first;
}
"#,
            r#"
module app;

fn main() {
    let value: i32 = core::wide::choose_first(1, 2, 3, 4, true);
    return value;
}
"#,
        ],
        "LNC0027",
        &[
            "error[LNC0027]: call resolution failed",
            "let value: i32 = core::wide::choose_first(1, 2, 3, 4, true);",
            "no supported function or method signature matches this receiver and argument list",
        ],
    );
}
