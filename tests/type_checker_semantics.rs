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
fn type_checker_resolves_shadowed_names_by_scope() {
    assert_gpu_type_check_ok(
        r#"
fn main() -> i32 {
    let value: i32 = 1;
    if (true) {
        let value: i32 = 2;
    }
    return value;
}
"#,
    );
}

#[test]
fn type_checker_accepts_boolean_logical_operands() {
    assert_gpu_type_check_ok(
        r#"
fn gate(left: bool, value: i32) -> bool {
    let low: bool = value >= 1;
    let high: bool = value < 9;
    let combined: bool = (low && high) || !left;
    if (combined && true) {
        return true;
    }
    return false;
}

fn main() {
    let flag: bool = gate(false, 3);
    if (flag || false) {
        return 1;
    }
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_bounded_scalar_type_aliases_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
type Count = i32;

fn keep(value: Count) -> Count {
    return value;
}

fn main() {
    let value: Count = keep(7);
    return value;
}
"#,
    );
}

#[test]
fn type_checker_accepts_bounded_scalar_type_alias_chains_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
type Raw = i32;
type Base = Raw;
type Count = Base;

fn keep(value: Count) -> Count {
    return value;
}

fn main() {
    let value: Count = keep(7);
    return value;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
type A = B;
type B = A;

fn main() {
    let value: A = 1;
    return value;
}
"#,
    );
}

#[test]
fn type_checker_accepts_bounded_nominal_type_aliases_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
struct Pair {
    left: i32,
    flag: bool,
}

type PairAlias = Pair;

fn keep(value: PairAlias) -> PairAlias {
    return value;
}

fn main() {
    let pair: PairAlias = Pair { left: 7, flag: true };
    let copied: Pair = keep(pair);
    return copied.left;
}
"#,
    );
}

#[test]
fn type_checker_accepts_bounded_array_type_aliases_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
type Four = [i32; 4];

fn first(values: Four) -> i32 {
    return values[0];
}

fn main(values: Four) {
    let value: i32 = first(values);
    return value;
}
"#,
    );
}

#[test]
fn type_checker_substitutes_bounded_generic_type_aliases_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
type Alias<T> = T;

fn keep_i32(value: Alias<i32>) -> Alias<i32> {
    return value;
}

fn main() {
    let value: Alias<i32> = keep_i32(7);
    return value;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
type Alias<T> = T;

fn main() {
    let value: Alias<i32> = true;
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_substitutes_bounded_generic_type_alias_chains_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
type Alias<T> = T;
type Id<T> = Alias<T>;

fn keep(value: Id<i32>) -> Id<i32> {
    return value;
}

fn main() {
    let value: Id<i32> = keep(7);
    return value;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
type Alias<T> = T;
type Id<T> = Alias<T>;

fn main() {
    let value: Id<i32> = true;
    return 0;
}
"#,
    );
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

fn make_pair_from_values(input_left: i32, input_flag: bool) -> Pair {
    return Pair { left: input_left, flag: input_flag };
}

fn get_left(pair: Pair) -> i32 {
    return pair.left;
}

fn main() {
    let pair: Pair = make_pair_from_values(7, true);
    return get_left(make_pair()) + get_left(pair);
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_self_receiver_field_access_on_gpu() {
    let src = r#"
struct Range {
    start: i32,
    end: i32,
}

impl Range {
    fn start(self) -> i32 {
        return self.start;
    }

    fn end(self: Range) -> i32 {
        return self.end;
    }

    fn is_empty(&self) -> bool {
        return self.start == self.end;
    }
}

fn main() {
    let range: Range = Range { start: 1, end: 4 };
    if (range.is_empty()) {
        return range.end();
    }
    return range.start();
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
fn type_checker_accepts_generic_struct_enum_values_through_helpers() {
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

fn main(input: Maybe<i32>) {
    let kept_box: Boxed<i32> = keep_box(Boxed { value: 7 });
    let kept_maybe: Maybe<i32> = keep_maybe(input);
    return keep(kept_box.value);
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn accepts_inferred_generic_function_calls() {
    assert_gpu_type_check_ok(
        r#"
fn keep<T>(value: T) -> T {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    let nested: i32 = keep(keep(7));
    let flag: bool = keep(true);
    return value;
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
fn keep<T>(value: T) -> T {
    return value;
}

fn outer<T>(value: T) -> T {
    return keep(value);
}

fn main() {
    let value: i32 = outer(7);
    return value;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn keep<T>(value: T) -> T {
    return value;
}

fn outer<T>(value: T) -> T {
    return keep(value);
}

fn main() {
    let flag: bool = outer(1);
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn keep<T>(value: T) -> T {
    return value;
}

fn main() {
    let flag: bool = keep(1);
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn choose<T>(left: T, right: T) -> T {
    return left;
}

fn main() {
    return choose(1, true);
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn choose<T>(left: T, right: T) -> T {
    return left;
}

fn main() {
    choose(1, true);
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_concrete_generic_struct_instances() {
    assert_gpu_type_check_ok(
        r#"
struct Range<T> {
    start: T,
    end: T,
}

fn make_range(start: i32, end: i32) -> Range<i32> {
    return Range { start: start, end: end };
}

fn main() {
    let range: Range<i32> = make_range(1, 4);
    return range.start;
}
"#,
    );

    assert_gpu_type_check_ok(
        r#"
struct Range<T> {
    start: T,
    end: T,
}

fn start_i32(range: Range<i32>) -> i32 {
    return range.start;
}

fn main() {
    let range: Range<i32> = Range { start: 1, end: 4 };
    return start_i32(range);
}
"#,
    );
}

#[test]
fn type_checker_accepts_concrete_generic_struct_literal_local_assignment() {
    assert_gpu_type_check_ok(
        r#"
struct Range<T> {
    start: T,
    end: T,
}

fn main() {
    let range: Range<i32> = Range { start: 1, end: 4 };
    return range.start - 1;
}
"#,
    );
}

#[test]
fn type_checker_accepts_trait_generic_bounds_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait Bound<T> {
    fn check(value: T) -> bool;
}

impl Bound<i32> for i32 {
    fn check(value: i32) -> bool {
        return value > 0;
    }
}

fn keep<T: Bound<T> >(value: T) -> T {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#,
    );
}

#[test]
fn type_checker_rejects_bounds_that_do_not_resolve_to_traits_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
struct Bound<T> {
    value: T,
}

fn keep<T: Bound<T> >(value: T) -> T {
    return value;
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_rejects_unknown_bound_type_arguments_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
trait Rel<T, U> {
    fn check(left: T, right: U) -> bool;
}

fn keep<T>(value: T) -> T where T: Rel<T, Missing> {
    return value;
}

fn main() {
    return 0;
}
"#,
    );
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
fn type_checker_rejects_unbound_generic_array_parameters_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
fn missing_len<T>(values: [T; N]) -> T {
    return values[0];
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
struct Bad<const N: usize> {
    values: [T; N],
}

fn main() {
    return 0;
}
"#,
    );
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

fn accept(value: MaybeI32) -> i32 {
    return 0;
}

fn main() {
    let value: MaybeI32 = make_value(7);
    let empty: MaybeI32 = None;
    let fallback: MaybeI32 = choose(empty);
    return accept(value) + accept(fallback);
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_rejects_invalid_enum_constructor_payloads_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
enum MaybeI32 {
    Some(i32),
    None,
}

fn main() {
    let value: MaybeI32 = Some(true);
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
enum MaybeI32 {
    Some(i32),
    None,
}

fn main() {
    let value: MaybeI32 = Some();
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
enum MaybeI32 {
    Some(i32),
    None,
}

fn main() {
    let value: MaybeI32 = None(1);
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_contextual_generic_enum_constructors_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
enum Maybe<T> {
    Some(T),
    None,
}

fn accept_maybe(value: Maybe<i32>) -> i32 {
    return 0;
}

fn main() {
    let value: Maybe<i32> = Some(1);
    return accept_maybe(value);
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
enum Result<T, E> {
    Ok(T),
    Err(E),
}

fn accept_result(value: Result<i32, bool>) -> i32 {
    return 0;
}

fn main() {
    let ok: Result<i32, bool> = Ok(1);
    let err: Result<i32, bool> = Err(false);
    return accept_result(ok) + accept_result(err);
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
enum Outcome<Good, Bad> {
    Succeed(Good),
    Fail(Bad),
}

fn accept_outcome(value: Outcome<i32, bool>) -> i32 {
    return 0;
}

fn main() {
    let fail: Outcome<i32, bool> = Fail(false);
    return accept_outcome(fail);
}
"#,
    );
}

#[test]
fn type_checker_rejects_invalid_generic_enum_constructor_payloads_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
enum Maybe<T> {
    Some(T),
    None,
}

fn main() {
    let value: Maybe<i32> = Some(true);
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
enum Maybe<T> {
    Some(T),
    None,
}

fn main() {
    let value: Maybe<i32> = Some();
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
enum Maybe<T> {
    Some(T),
    None,
}

fn main() {
    let value: Maybe<i32> = None(1);
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
enum Result<T, E> {
    Ok(T),
    Err(E),
}

fn main() {
    let value: Result<i32, bool> = Ok(true);
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_symbolic_generic_enum_constructor_returns_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
enum Maybe<T> {
    Some(T),
    None,
}

fn wrap<T>(value: T) -> Maybe<T> {
    return Some(value);
}

fn unwrap_or<T>(value: Maybe<T>, fallback: T) -> T {
    return match (value) {
        Some(inner) -> inner,
        None -> fallback,
    };
}

fn main() {
    return unwrap_or(wrap(1), 0);
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
enum Maybe<T> {
    Some(T),
    None,
}

fn wrong<T>(value: T) -> Maybe<T> {
    return value;
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
enum Maybe<T> {
    Some(T),
    None,
}

fn wrong<T>(value: bool) -> Maybe<T> {
    return Some(value);
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_i32_slice_parameters_and_indexing() {
    let src = r#"
fn first(values: [i32]) -> i32 {
    return values[0];
}

fn main(values: [i32]) {
    return first(values);
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_concrete_identifier_array_returns_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
fn copy(values: [i32; 4]) -> [i32; 4] {
    return values;
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let copied: [i32; 4] = copy(values);
    return copied[0];
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
fn local_copy(values: [i32; 4]) -> [i32; 4] {
    let local: [i32; 4] = values;
    return local;
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let copied: [i32; 4] = local_copy(values);
    return copied[0];
}
"#,
    );
}

#[test]
fn type_checker_accepts_concrete_i32_array_literal_returns_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
fn values() -> [i32; 4] {
    return [1, 2, 3, 4];
}

fn with_trailing_comma() -> [i32; 2] {
    return [1, 2,];
}

fn empty() -> [i32; 0] {
    return [];
}

fn filled(value: i32) -> [i32; 4] {
    return [value, value, value, value];
}

fn mixed(value: i32) -> [i32; 4] {
    return [value, 1, value, 2];
}

fn reversed(values: [i32; 4]) -> [i32; 4] {
    return [values[3], values[2], values[1], values[0]];
}

fn selected(values: [i32; 4], index: i32) -> [i32; 2] {
    return [values[index], values[0]];
}

fn main() {
    let source: [i32; 4] = [3, 1, 4, 1];
    let direct: [i32; 4] = values();
    let trailing: [i32; 2] = with_trailing_comma();
    let empty_values: [i32; 0] = empty();
    let repeated: [i32; 4] = filled(direct[0]);
    let mixed_values: [i32; 4] = mixed(repeated[1]);
    let reversed_values: [i32; 4] = reversed(source);
    let selected_values: [i32; 2] = selected(reversed_values, 1);
    return direct[0] + trailing[1] + mixed_values[3] + selected_values[0];
}
"#,
    );
}

#[test]
fn type_checker_accepts_concrete_declared_array_call_results_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
fn pair(left: i32, right: i32) -> [i32; 2] {
    return [left, right];
}

fn filled(value: i32) -> [i32; 4] {
    return [value, value, value, value];
}

fn main() {
    let pair_values: [i32; 2] = pair(1, 2);
    let filled_values: [i32; 4] = filled(pair_values[0]);
    return filled_values[1];
}
"#,
    );
}

#[test]
fn type_checker_rejects_array_returns_outside_bounded_gpu_slice() {
    assert_gpu_type_check_rejects(
        r#"
fn bool_filled(value: bool) -> [i32; 4] {
    return [value, value, value, value];
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn wrong_len() -> [i32; 4] {
    return [1, 2];
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn wrong_elem() -> [i32; 2] {
    return [1, true];
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn bool_index(values: [i32; 4], index: bool) -> [i32; 1] {
    return [values[index]];
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn index_scalar(value: i32) -> [i32; 1] {
    return [value[0]];
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn copy_mismatched_len(values: [i32; 2]) -> [i32; 4] {
    return values;
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn copy_wrong_generic_elem<T, const N: usize>(values: [T; N]) -> [bool; N] {
    return values;
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn copy_wrong_generic_len<T, const N: usize, const M: usize>(values: [T; N]) -> [T; M] {
    return values;
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn pair(left: i32, right: i32) -> [i32; 2] {
    return [left, right];
}

fn main() {
    let values: [i32; 3] = pair(1, 2);
    return values[0];
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn copy_generic<T, const N: usize>(values: [T; N]) -> [T; N] {
    return values;
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let copied: [i32; 5] = copy_generic(values);
    return copied[0];
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
fn copy_generic<T, const N: usize>(values: [T; N]) -> [T; N] {
    return values;
}

fn copy_wrong_call_return(values: [i32; 4]) -> [i32; 5] {
    return copy_generic(values);
}

fn main() {
    return 0;
}
"#,
    );
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
    let flag: bool = 1 || false;
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
struct Pair {
    left: i32,
}

impl Pair {
    fn read(self) -> i32 {
        return self.right;
    }
}

fn main() {
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

#[path = "type_checker_semantics/trait_methods_control.rs"]
mod trait_methods_control;
