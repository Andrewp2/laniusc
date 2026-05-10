mod common;

use laniusc::compiler::CompileError;

fn assert_gpu_type_check_ok(src: &str) {
    common::type_check_source_with_timeout(src).expect("source should pass GPU type checking");
}

fn assert_gpu_type_check_error(src: &str, expected: &str) {
    let err = common::type_check_source_with_timeout(src)
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
fn type_checker_accepts_struct_literals_and_member_access() {
    let src = r#"
struct Pair {
    left: i32,
    flag: bool,
}

fn main() {
    let pair: Pair = Pair { left: 7, flag: 1 < 2 };
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
fn type_checker_accepts_struct_field_assignment() {
    let src = r#"
struct Pair {
    left: i32,
    flag: bool,
}

fn main() {
    let pair: Pair = Pair { left: 7, flag: true };
    pair.left = 8;
    pair.flag = false;
    return pair.left;
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
fn type_checker_accepts_generic_type_parameters_in_declarations() {
    let src = r#"
fn identity<T>(value: T) -> T {
    return value;
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_generic_type_parameters_in_local_annotations() {
    let src = r#"
fn keep<T>(value: T) -> T {
    let copied: T = value;
    return copied;
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_bounded_generic_function_calls() {
    let src = r#"
fn identity<T>(value: T) -> T {
    return value;
}

fn choose<T>(left: T, right: T) -> T {
    return left;
}

fn main() {
    let value: i32 = identity(7);
    let flag: bool = choose(true, false);
    if (flag) {
        return value;
    }
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_type_alias_declarations() {
    let src = r#"
type Count = i32;
type Flag = bool;

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_type_alias_uses() {
    let src = r#"
type Count = i32;
type OtherCount = Count;
type Flag = bool;

fn add_one(value: OtherCount) -> Count {
    let next: Count = value + 1;
    return next;
}

fn main() {
    let flag: Flag = true;
    if (flag) {
        return add_one(1);
    }
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_generic_type_alias_uses() {
    let src = r#"
enum Maybe<T> {
    Some(T),
    None,
}

type MaybeI32 = Maybe<i32>;

fn keep(value: MaybeI32) -> MaybeI32 {
    let copied: MaybeI32 = value;
    return copied;
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_generic_type_alias_parameter_substitution() {
    let src = r#"
struct Boxed<T> {
    value: T,
}

type Alias<T> = Boxed<T>;

fn keep(value: Alias<i32>) -> Alias<i32> {
    let copied: Alias<i32> = value;
    return copied;
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_generic_enum_declarations() {
    let src = r#"
enum Maybe<T> {
    Some(T),
    None,
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_concrete_generic_enum_type_uses() {
    let src = r#"
enum Maybe<T> {
    Some(T),
    None,
}

enum Fallible<T, E> {
    Ok(T),
    Err(E),
}

fn keep_maybe(value: Maybe<i32>) -> Maybe<i32> {
    let copied: Maybe<i32> = value;
    return copied;
}

fn keep_result(value: Fallible<i32, bool>) -> Fallible<i32, bool> {
    let copied: Fallible<i32, bool> = value;
    return copied;
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_concrete_generic_struct_type_uses() {
    let src = r#"
struct Boxed<T> {
    value: T,
}

fn keep_box(value: Boxed<i32>) -> Boxed<i32> {
    let copied: Boxed<i32> = value;
    return copied;
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_concrete_generic_struct_literals_and_members() {
    let src = r#"
struct Pair<T> {
    left: T,
    right: T,
}

fn main() {
    let pair: Pair<i32> = Pair { left: 7, right: 4 };
    let left: i32 = pair.left;
    return left + pair.right;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_bounded_impl_method_calls() {
    let src = r#"
struct Boxed<T> {
    value: T,
}

impl<T> Boxed<T> {
    fn value(receiver: Boxed<T>) -> T {
        return receiver.value;
    }

    fn keep(receiver: Boxed<T>, fallback: T) -> T {
        return fallback;
    }
}

fn main() {
    let boxed: Boxed<i32> = Boxed { value: 7 };
    let value: i32 = boxed.value();
    return boxed.keep(value);
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_bounded_trait_impl_conformance_and_method_calls() {
    let src = r#"
struct Boxed<T> {
    value: T,
}

trait EqBoxed<T> {
    fn eq(left: Boxed<T>, right: Boxed<T>) -> bool;
    fn ne(left: Boxed<T>, right: Boxed<T>) -> bool;
}

impl EqBoxed<i32> for Boxed<i32> {
    fn eq(left: Boxed<i32>, right: Boxed<i32>) -> bool {
        return left.value == right.value;
    }

    fn ne(left: Boxed<i32>, right: Boxed<i32>) -> bool {
        return left.value != right.value;
    }
}

fn main() {
    let left: Boxed<i32> = Boxed { value: 7 };
    let right: Boxed<i32> = Boxed { value: 8 };
    let same: bool = left.eq(left);
    let different: bool = left.ne(right);
    if (same || different) {
        return 1;
    }
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_trait_bound_method_calls_on_generic_params() {
    let src = r#"
trait Eq<T> {
    fn eq(left: T, right: T) -> bool;
}

fn same<T: Eq<T>>(left: T, right: T) -> bool {
    return left.eq(right);
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_multiple_trait_bound_method_calls_on_generic_params() {
    let src = r#"
trait Eq<T> {
    fn eq(left: T, right: T) -> bool;
}

trait Hash<T> {
    fn hash(value: T) -> u32;
}

fn same_hash<T: Eq<T> + Hash<T>>(left: T, right: T) -> bool {
    let same: bool = left.eq(right);
    let left_hash: u32 = left.hash();
    let right_hash: u32 = right.hash();
    return same && left_hash == right_hash;
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_generic_struct_declarations() {
    let src = r#"
struct Boxed<T> {
    value: T,
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_const_generic_struct_declarations() {
    let src = r#"
struct ArrayHeader<T, const N: usize> {
    value: T,
    len: usize,
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
fn type_checker_accepts_fixed_array_return_values() {
    let src = r#"
fn keep(values: [i32; 4]) -> [i32; 4] {
    return values;
}

fn make_pair(left: i32, right: i32) -> [i32; 2] {
    return [left, right];
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let copied: [i32; 4] = keep(values);
    let pair: [i32; 2] = make_pair(copied[0], copied[2]);
    return pair[0] + pair[1];
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_bounded_for_loops_over_arrays_and_ranges() {
    let src = r#"
struct Range<T> {
    start: T,
    end: T,
}

fn main() {
    let values: [i32; 3] = [1, 2, 3];
    let total: i32 = 0;
    for value in values {
        total += value;
    }
    let range: Range<i32> = Range { start: 0, end: 3 };
    for index in range {
        total += index;
    }
    return total;
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
fn type_checker_accepts_enum_constructors() {
    let src = r#"
enum MaybeI32 {
    Some(i32),
    None,
}

fn main() {
    let value: MaybeI32 = Some(1);
    let empty: MaybeI32 = None;
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_enum_function_parameters_and_returns() {
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
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_generic_enum_constructors_with_concrete_context() {
    let src = r#"
enum Maybe<T> {
    Some(T),
    None,
}

fn make_some(value: i32) -> Maybe<i32> {
    return Some(value);
}

fn make_none() -> Maybe<i32> {
    return None;
}

fn main() {
    let value: Maybe<i32> = Some(1);
    let empty: Maybe<i32> = None;
    let copied: Maybe<i32> = make_some(2);
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_match_arm_result_types() {
    let src = r#"
fn choose(value: i32, fallback: i32) -> i32 {
    let out: i32 = match (value) {
        0 -> fallback,
        _ -> value,
    };
    return out;
}

fn main() {
    return choose(0, 7);
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_match_tuple_pattern_bindings() {
    let src = r#"
enum Maybe<T> {
    Some(T),
    None,
}

fn unwrap_or(value: Maybe<i32>, fallback: i32) -> i32 {
    let out: i32 = match (value) {
        Some(inner) -> inner,
        None -> fallback,
    };
    return out;
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_generic_match_returning_type_parameter() {
    let src = r#"
enum Maybe<T> {
    Some(T),
    None,
}

fn unwrap_or<T>(value: Maybe<T>, fallback: T) -> T {
    return match (value) {
        Some(inner) -> inner,
        None -> fallback,
    };
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_rejects_match_arm_result_type_mismatch() {
    let src = r#"
fn choose(value: i32) -> i32 {
    let out: i32 = match (value) {
        0 -> 1,
        _ -> true,
    };
    return out;
}
"#;

    assert_gpu_type_check_error(src, "match arm type mismatch");
}

#[test]
fn type_checker_rejects_enum_constructor_argument_type_mismatch() {
    let src = r#"
enum MaybeI32 {
    Some(i32),
    None,
}

fn main() {
    let value: MaybeI32 = Some(true);
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "enum constructor `Some` argument type mismatch");
}

#[test]
fn type_checker_rejects_enum_constructor_argument_count_mismatch() {
    let src = r#"
enum MaybeI32 {
    Some(i32),
    None,
}

fn main() {
    let value: MaybeI32 = Some();
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "enum constructor `Some` argument count mismatch");
}

#[test]
fn type_checker_rejects_generic_enum_constructor_argument_type_mismatch() {
    let src = r#"
enum Maybe<T> {
    Some(T),
    None,
}

fn main() {
    let value: Maybe<i32> = Some(true);
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "enum constructor `Some` argument type mismatch");
}

#[test]
fn type_checker_rejects_generic_struct_literal_field_type_mismatch() {
    let src = r#"
struct Pair<T> {
    left: T,
    right: T,
}

fn main() {
    let pair: Pair<i32> = Pair { left: true, right: 4 };
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch");
}

#[test]
fn type_checker_rejects_impl_method_call_argument_type_mismatch() {
    let src = r#"
struct Boxed<T> {
    value: T,
}

impl<T> Boxed<T> {
    fn keep(receiver: Boxed<T>, fallback: T) -> T {
        return fallback;
    }
}

fn main() {
    let boxed: Boxed<i32> = Boxed { value: 7 };
    let value: i32 = boxed.keep(true);
    return value;
}
"#;

    assert_gpu_type_check_error(src, "method `keep` argument 0 type mismatch");
}

#[test]
fn type_checker_rejects_trait_impl_missing_required_method() {
    let src = r#"
trait Eq<T> {
    fn eq(left: T, right: T) -> bool;
    fn ne(left: T, right: T) -> bool;
}

impl Eq<i32> for i32 {
    fn eq(left: i32, right: i32) -> bool {
        return left == right;
    }
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "missing method `ne`");
}

#[test]
fn type_checker_rejects_trait_impl_method_signature_mismatch() {
    let src = r#"
trait Eq<T> {
    fn eq(left: T, right: T) -> bool;
}

impl Eq<i32> for i32 {
    fn eq(left: i32, right: bool) -> bool {
        return false;
    }
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "method `eq` parameter 2");
}

#[test]
fn type_checker_rejects_missing_trait_bound_for_generic_method_call() {
    let src = r#"
trait Eq<T> {
    fn eq(left: T, right: T) -> bool;
}

fn same<T>(left: T, right: T) -> bool {
    return left.eq(right);
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "method `eq` not found");
}

#[test]
fn type_checker_rejects_trait_bound_method_argument_mismatch() {
    let src = r#"
trait Eq<T> {
    fn eq(left: T, right: T) -> bool;
}

fn bad<T: Eq<T>>(left: T) -> bool {
    return left.eq(true);
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "method `eq` argument 0");
}

#[test]
fn type_checker_rejects_cross_enum_constructor_assignment() {
    let src = r#"
enum MaybeI32 {
    Some(i32),
    None,
}

enum Other {
    Empty,
}

fn main() {
    let value: MaybeI32 = Empty;
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "let type mismatch");
}

#[test]
fn type_checker_rejects_concrete_return_for_generic_type_parameter() {
    let src = r#"
fn bad<T>(value: T) -> T {
    return 1;
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "return type mismatch");
}

#[test]
fn type_checker_rejects_concrete_initializer_for_generic_type_parameter() {
    let src = r#"
fn bad<T>(value: T) -> T {
    let other: T = 1;
    return value;
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "let type mismatch");
}

#[test]
fn type_checker_rejects_generic_function_call_argument_type_mismatch() {
    let src = r#"
fn identity<T>(value: T) -> T {
    return value;
}

fn main() {
    let value: bool = identity(1);
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "function `identity` argument 0 type mismatch");
}

#[test]
fn type_checker_rejects_struct_field_assignment_type_mismatch() {
    let src = r#"
struct Pair {
    left: i32,
    flag: bool,
}

fn main() {
    let pair: Pair = Pair { left: 7, flag: true };
    pair.left = false;
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "assignment type mismatch");
}

#[test]
fn type_checker_rejects_struct_literal_field_type_mismatch() {
    let src = r#"
struct Pair {
    left: i32,
    flag: bool,
}

fn main() {
    let pair: Pair = Pair { left: true, flag: false };
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "AssignMismatch");
}

#[test]
fn type_checker_rejects_unknown_struct_literal_field() {
    let src = r#"
struct Pair {
    left: i32,
    flag: bool,
}

fn main() {
    let pair: Pair = Pair { right: 7, flag: true };
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "InvalidMemberAccess");
}

#[test]
fn type_checker_rejects_missing_struct_literal_field() {
    let src = r#"
struct Pair {
    left: i32,
    flag: bool,
}

fn main() {
    let pair: Pair = Pair { left: 7 };
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "InvalidMemberAccess");
}

#[test]
fn type_checker_rejects_unknown_struct_member_access() {
    let src = r#"
struct Pair {
    left: i32,
    flag: bool,
}

fn main() {
    let pair: Pair = Pair { left: 7, flag: true };
    let value: i32 = pair.right;
    return value;
}
"#;

    assert_gpu_type_check_error(src, "InvalidMemberAccess");
}

#[test]
fn type_checker_rejects_member_access_on_non_structs() {
    let src = r#"
fn main() {
    let value: i32 = 7;
    let field: i32 = value.left;
    return field;
}
"#;

    assert_gpu_type_check_error(src, "InvalidMemberAccess");
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

    assert_gpu_type_check_error(src, "assignment type mismatch");
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

    assert_gpu_type_check_error(src, "AssignMismatch");
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

    assert_gpu_type_check_error(src, "AssignMismatch");
}

#[test]
fn type_checker_recognizes_str_type_annotations() {
    let src = r#"
fn main() {
    let text: str = 1;
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "let type mismatch");
}

#[test]
fn type_checker_recognizes_str_function_parameters() {
    let src = r#"
fn takes_text(value: str) -> i32 {
    return 0;
}

fn main() {
    return takes_text(1);
}
"#;

    assert_gpu_type_check_error(src, "function `takes_text` argument 0 type mismatch");
}

#[test]
fn type_checker_recognizes_str_return_types() {
    let src = r#"
fn make_text() -> str {
    return 1;
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "return type mismatch");
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

    assert_gpu_type_check_error(src, "return type mismatch");
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

    assert_gpu_type_check_error(src, "ConditionType");
}

#[test]
fn type_checker_rejects_bool_literal_in_integer_expression() {
    let src = r#"
fn main() {
    let value: i32 = true + 1;
    return value;
}
"#;

    assert_gpu_type_check_error(src, "let type mismatch");
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

    assert_gpu_type_check_error(src, "const type mismatch");
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

    assert_gpu_type_check_error(src, "ConditionType");
}

#[test]
fn type_checker_rejects_for_loop_over_non_iterable_value() {
    let src = r#"
fn main() {
    for value in 1 {
        print(value);
    }
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "for iterable type mismatch");
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

    assert_gpu_type_check_error(src, "function `add` argument count mismatch");
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

    assert_gpu_type_check_error(src, "function `as_int` argument 0 type mismatch");
}

#[test]
fn type_checker_rejects_extern_call_argument_type_mismatch() {
    let src = r#"
extern fn host_log_i32(value: i32);

fn main() {
    let flag: bool = true;
    host_log_i32(flag);
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "function `host_log_i32` argument 0 type mismatch");
}

#[test]
fn type_checker_keeps_void_extern_return_before_following_function() {
    let src = r#"
extern fn notify();

fn later() -> i32 {
    return 7;
}

fn main() {
    let value: i32 = notify();
    return value;
}
"#;

    assert_gpu_type_check_error(src, "let type mismatch");
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

    assert_gpu_type_check_error(src, "CallMismatch");
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

    assert_gpu_type_check_error(src, "CallMismatch");
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

    assert_gpu_type_check_error(src, "AssignMismatch");
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

    assert_gpu_type_check_error(src, "AssignMismatch");
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

    assert_gpu_type_check_error(src, "assignment type mismatch");
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

    assert_gpu_type_check_error(src, "array literal type mismatch");
}

#[test]
fn type_checker_rejects_array_return_length_mismatch() {
    let src = r#"
fn bad() -> [i32; 2] {
    return [1, 2, 3];
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_error(src, "return type mismatch");
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

    assert_gpu_type_check_error(src, "let type mismatch");
}
