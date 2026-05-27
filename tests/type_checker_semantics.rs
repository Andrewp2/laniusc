mod common;

use laniusc::compiler::CompileError;
use rand::{Rng, SeedableRng, rngs::StdRng};

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
fn type_checker_accepts_generated_deep_let_chain() {
    let mut src = String::from("fn main() -> i32 {\n    let v0: i32 = 1;\n");
    for i in 1..80 {
        let prev = i - 1;
        let add = (i * 17 + 3) % 11;
        src.push_str(&format!("    let v{i}: i32 = v{prev} + {add};\n"));
    }
    src.push_str("    return v79;\n}\n");

    assert_gpu_type_check_ok(&src);
}

#[test]
fn type_checker_accepts_generated_call_argument_shapes() {
    let mut rng = StdRng::seed_from_u64(0x7479_636b_6172_6773);
    let mut names = Vec::new();
    while names.len() < 24 {
        let candidate = random_ident(&mut rng);
        if !names.contains(&candidate) {
            names.push(candidate);
        }
    }

    let id_fn = &names[0];
    let id_param = &names[1];
    let local = &names[2];
    let mut src = format!("fn {id_fn}({id_param}: i32) -> i32 {{\n    return {id_param};\n}}\n");
    for arity in 0..5 {
        let fn_name = &names[3 + arity];
        let params = (0..arity)
            .map(|i| format!("{}: i32", names[8 + arity * 2 + i]))
            .collect::<Vec<_>>()
            .join(", ");
        let body = if arity == 0 {
            String::from("11")
        } else {
            names[8 + arity * 2..8 + arity * 2 + arity].join(" + ")
        };
        src.push_str(&format!(
            "fn {fn_name}({params}) -> i32 {{\n    return {body};\n}}\n"
        ));
    }

    src.push_str(&format!(
        "fn main() -> i32 {{\n    let {local}: i32 = {id_fn}(3);\n"
    ));
    for arity in 0..5 {
        let fn_name = &names[3 + arity];
        let args = match arity {
            0 => String::new(),
            1 => local.to_owned(),
            2 => format!("{local}, {id_fn}(5)"),
            3 => format!("{id_fn}(1), {local} + 2, 7"),
            _ => format!("{local}, {id_fn}(4), 8 + 9, {id_fn}({local})"),
        };
        src.push_str(&format!("    let r{arity}: i32 = {fn_name}({args});\n"));
    }
    src.push_str("    return r0 + r1 + r2 + r3 + r4;\n}\n");

    assert_gpu_type_check_ok(&src);
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

fn random_ident(rng: &mut StdRng) -> String {
    const FIRST: &[u8] = b"abcdefghijklmnopqrstuvwxyz";
    const REST: &[u8] = b"abcdefghijklmnopqrstuvwxyz0123456789";
    let mut ident = String::new();
    ident.push(FIRST[rng.random_range(0..FIRST.len())] as char);
    for _ in 0..rng.random_range(3..=9) {
        ident.push(REST[rng.random_range(0..REST.len())] as char);
    }
    ident
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
fn type_checker_accepts_bounded_generic_type_alias_declarations_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
type Alias<T> = T;
type Buffer<T, const N: usize> = [T; N];

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_bounded_generic_type_alias_annotations_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
type Alias<T> = T;

fn keep<T>(value: Alias<T>) -> Alias<T> {
    let copied: Alias<T> = value;
    return copied;
}

fn main() {
    return 0;
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
    assert_gpu_type_check_rejects_with_code(
        r#"
type Alias<T> = T;

fn main() {
    let value: Alias<i32> = true;
    return 0;
}
"#,
        "AssignMismatch",
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
    assert_gpu_type_check_rejects_with_code(
        r#"
type Alias<T> = T;
type Id<T> = Alias<T>;

fn main() {
    let value: Id<i32> = true;
    return 0;
}
"#,
        "AssignMismatch",
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
    return 0;
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
fn type_checker_accepts_simple_generic_function_calls_with_inferred_type_arguments() {
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
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects_with_code(
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
        "AssignMismatch",
    );
    assert_gpu_type_check_rejects_with_code(
        r#"
fn keep<T>(value: T) -> T {
    return value;
}

fn main() {
    let flag: bool = keep(1);
    return 0;
}
"#,
        "AssignMismatch",
    );
    assert_gpu_type_check_rejects_with_code(
        r#"
fn choose<T>(left: T, right: T) -> T {
    return left;
}

fn main() {
    return choose(1, true);
}
"#,
        "AssignMismatch",
    );
    assert_gpu_type_check_rejects_with_code(
        r#"
fn choose<T>(left: T, right: T) -> T {
    return left;
}

fn main() {
    choose(1, true);
    return 0;
}
"#,
        "AssignMismatch",
    );
}

#[test]
fn type_checker_rejects_direct_generic_aggregate_call_returns_until_substituted_refs_exist() {
    assert_gpu_type_check_rejects_with_code(
        r#"
struct Wrapper<T> {
    value: T,
}

fn wrap<T>(value: T) -> Wrapper<T> {
    return Wrapper { value: value };
}

fn main() {
    let wrapped: Wrapper<i32> = wrap(1);
    return 0;
}
"#,
        "AssignMismatch",
    );
    assert_gpu_type_check_rejects_with_code(
        r#"
struct Wrapper<T> {
    value: T,
}

fn wrap<T>(value: T) -> Wrapper<T> {
    return Wrapper { value: value };
}

fn main() {
    let wrapped: Wrapper<bool> = wrap(1);
    return 0;
}
"#,
        "AssignMismatch",
    );
}

#[test]
fn type_checker_accepts_concrete_generic_struct_instances() {
    // Generic struct declarations can be parsed and type-checked for concrete
    // instances here. Non-constructor symbolic generic returns, monomorphized
    // backend lowering, and cross-module generic use remain separate GPU work.
    assert_gpu_type_check_ok(
        r#"
struct Range<T> {
    start: T,
    end: T,
}

struct RangeInclusive<T> {
    start: T,
    end: T,
}

fn make_range(start: i32, end: i32) -> Range<i32> {
    return Range { start: start, end: end };
}

fn main() {
    return 0;
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
    return 0;
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
fn type_checker_accepts_multiple_trait_generic_bounds_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait Rel<T, U> {
    fn check(left: T, right: U) -> bool;
}

trait CopyLike<T> {
    fn check(value: T) -> bool;
}

fn keep<T, U>(value: T, other: U) -> T where T: Rel<T, U> + CopyLike<T>, U: CopyLike<U>, {
    return value;
}

fn main() {
    return 0;
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
fn type_checker_accepts_generic_array_and_slice_elements_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
fn first<T, const N: usize>(values: [T; N]) -> T {
    return values[0];
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let value: i32 = first(values);
    return value;
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
fn first_copy<T, const N: usize>(values: [T; N]) -> T {
    let copy: [T; N] = values;
    return copy[0];
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let value: i32 = first_copy(values);
    return value;
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
fn copy_generic<T, const N: usize>(values: [T; N]) -> [T; N] {
    return values;
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
fn copy_generic<T, const N: usize>(values: [T; N]) -> [T; N] {
    return values;
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let copied: [i32; 4] = copy_generic(values);
    return copied[0];
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
fn copy_generic<T, const N: usize>(values: [T; N]) -> [T; N] {
    return values;
}

fn copy_i32(values: [i32; 4]) -> [i32; 4] {
    return copy_generic(values);
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let copied: [i32; 4] = copy_i32(values);
    return copied[0];
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
fn first<T, const N: usize>(values: [T; N]) -> T {
    return values[0];
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
fn first_slice<T>(values: [T]) -> T {
    return values[0];
}

fn main(values: [i32]) {
    let value: i32 = first_slice(values);
    return value;
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
fn first_slice<T>(values: [T]) -> T {
    return values[0];
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
struct ArrayVec<T, const N: usize> {
    values: [T; N],
    len: usize,
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
struct ArrayVec<T, const N: usize> {
    values: [T; N],
    len: usize,
}

fn first_vec(vec: ArrayVec<i32, 4>) -> i32 {
    return vec.values[0];
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_rejects_generic_struct_literal_array_fields_until_const_substitution() {
    assert_gpu_type_check_rejects_with_code(
        r#"
struct ArrayVec<T, const N: usize> {
    values: [T; N],
    len: usize,
}

fn first_vec(vec: ArrayVec<i32, 4>) -> i32 {
    return vec.values[0];
}

fn main() {
    let vec: ArrayVec<i32, 4> = ArrayVec { values: [3, 1, 4, 1], len: 4 };
    return first_vec(vec);
}
"#,
        "AssignMismatch",
    );
}

#[test]
fn type_checker_rejects_invalid_generic_array_element_returns_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
fn wrong<T, const N: usize>(values: [T; N]) -> bool {
    return values[0];
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects_with_code(
        r#"
fn first<T, const N: usize>(values: [T; N]) -> T {
    return values[0];
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let flag: bool = first(values);
    return 0;
}
"#,
        "AssignMismatch",
    );
    assert_gpu_type_check_rejects_with_code(
        r#"
fn first_slice<T>(values: [T]) -> T {
    return values[0];
}

fn main(values: [i32]) {
    let flag: bool = first_slice(values);
    return 0;
}
"#,
        "AssignMismatch",
    );
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
    assert_gpu_type_check_rejects(
        r#"
fn wrong_whole_array<T, const N: usize>(values: [T; N]) -> T {
    return values;
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

fn main() {
    let value: Maybe<i32> = Some(1);
    return 0;
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
enum Result<T, E> {
    Ok(T),
    Err(E),
}

fn main() {
    let ok: Result<i32, bool> = Ok(1);
    let err: Result<i32, bool> = Err(false);
    return 0;
}
"#,
    );
    assert_gpu_type_check_ok(
        r#"
enum Outcome<Good, Bad> {
    Succeed(Good),
    Fail(Bad),
}

fn main() {
    let fail: Outcome<i32, bool> = Fail(false);
    return 0;
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

fn main() {
    return 0;
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
    return 0;
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
    return 0;
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
    return 0;
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

#[test]
fn type_checker_accepts_concrete_inherent_method_calls_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
struct Range {
    start: i32,
    end: i32,
}

impl Range {
    fn contains(receiver: Range, value: i32) -> bool {
        return value >= receiver.start && value < receiver.end;
    }
}

fn make_range() -> Range {
    return Range { start: 1, end: 4 };
}

fn read_direct() -> i32 {
    if (make_range().contains(2)) {
        return 1;
    }
    return 0;
}

fn main() {
    let range: Range = Range { start: 1, end: 4 };
    if (range.contains(2)) {
        return 1;
    }
    return 0;
}
"#,
    );

    assert_gpu_type_check_ok(
        r#"
struct Range<T> {
    start: T,
    end: T,
}

impl Range<i32> {
    fn start(self) -> i32 {
        return self.start;
    }

    fn end(self: Range<i32>) -> i32 {
        return self.end;
    }

    fn contains(&self, value: i32) -> bool {
        return value >= self.start && value < self.end;
    }
}

fn read(range: Range<i32>) -> i32 {
    if (range.contains(2)) {
        return range.start();
    }
    return range.end();
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_rejects_with_code(
        r#"
struct Range {
    start: i32,
    end: i32,
}

impl Range {
    fn contains(&self, value: i32) -> bool {
        return value >= self.start && value < self.end;
    }
}

fn main() {
    let range: Range = Range { start: 1, end: 4 };
    if (range.contains(true)) {
        return 1;
    }
    return 0;
}
"#,
        "AssignMismatch",
    );

    assert_gpu_type_check_rejects_with_code(
        r#"
struct Range {
    start: i32,
    end: i32,
}

impl Range {
    fn contains(value: i32) -> bool {
        return value > 0;
    }
}

fn main() {
    let range: Range = Range { start: 1, end: 4 };
    if (range.contains(2)) {
        return 1;
    }
    return 0;
}
"#,
        "CallMismatch",
    );
}

#[test]
fn type_checker_accepts_trait_declarations_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
pub trait Eq<T> {
    pub fn eq(left: T, right: T) -> bool;
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_trait_impl_declarations_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait Eq<T> {
    fn eq(left: T, right: T) -> bool;
}

struct Target {
    value: i32,
}

impl Eq<Target> for Target {
    fn eq(left: Target, right: Target) -> bool {
        return true;
    }
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_rejects_trait_impls_whose_trait_does_not_resolve_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
struct Eq<T> {
    value: T,
}

struct Target {
    value: i32,
}

impl Eq<Target> for Target {
    fn eq(left: Target, right: Target) -> bool {
        return true;
    }
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_rejects_trait_impls_missing_required_methods_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
trait Eq<T> {
    fn eq(left: T, right: T) -> bool;
    fn ne(left: T, right: T) -> bool;
}

struct Target {
    value: i32,
}

impl Eq<Target> for Target {
    fn eq(left: Target, right: Target) -> bool {
        return true;
    }
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_rejects_trait_impl_methods_with_wrong_arity_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
trait Eq<T> {
    fn eq(left: T, right: T) -> bool;
}

struct Target {
    value: i32,
}

impl Eq<Target> for Target {
    fn eq(left: Target) -> bool {
        return true;
    }
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_rejects_trait_impl_methods_with_wrong_parameter_type_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
trait Eq<T> {
    fn eq(left: T, right: T) -> bool;
}

struct Target {
    value: i32,
}

impl Eq<Target> for Target {
    fn eq(left: Target, right: i32) -> bool {
        return true;
    }
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_rejects_trait_impl_methods_with_wrong_return_type_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
trait Measure<T> {
    fn get(value: T) -> bool;
}

struct Target {
    value: i32,
}

impl Measure<Target> for Target {
    fn get(value: Target) -> i32 {
        return 1;
    }
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_validates_trait_impl_reference_signatures_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait Borrow<T> {
    fn borrow(value: &T) -> &T;
}

struct Target {
    value: i32,
}

impl Borrow<Target> for Target {
    fn borrow(value: &Target) -> &Target {
        return value;
    }
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
trait Borrow<T> {
    fn borrow(value: &T) -> &T;
}

struct Target {
    value: i32,
}

impl Borrow<Target> for Target {
    fn borrow(value: &i32) -> &Target {
        return value;
    }
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_validates_trait_impl_array_signatures_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait First<T> {
    fn first(values: [T; 4]) -> T;
}

struct Target {
    value: i32,
}

impl First<i32> for Target {
    fn first(values: [i32; 4]) -> i32 {
        return values[0];
    }
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
trait First<T> {
    fn first(values: [T; 4]) -> T;
}

struct Target {
    value: i32,
}

impl First<i32> for Target {
    fn first(values: [i32; 3]) -> i32 {
        return values[0];
    }
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_validates_trait_impl_generic_instance_signatures_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
struct Boxed<T> {
    value: T,
}

trait Unbox<T> {
    fn unbox(value: Boxed<T>) -> T;
}

struct Target {
    value: i32,
}

impl Unbox<i32> for Target {
    fn unbox(value: Boxed<i32>) -> i32 {
        return 0;
    }
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
struct Boxed<T> {
    value: T,
}

trait Unbox<T> {
    fn unbox(value: Boxed<T>) -> T;
}

struct Target {
    value: i32,
}

impl Unbox<i32> for Target {
    fn unbox(value: Boxed<bool>) -> i32 {
        return 0;
    }
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_trait_where_clauses_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait Boxed<T> {
    fn check(value: T) -> bool;
}

fn keep<T>(value: T) -> T where T: Boxed<T> {
    return value;
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_enforces_called_trait_where_clauses_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait Boxed<T> {
    fn check(value: T) -> bool;
}

impl Boxed<i32> for i32 {
    fn check(value: i32) -> bool {
        return true;
    }
}

fn keep<T>(value: T) -> T where T: Boxed<T> {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
trait Boxed<T> {
    fn check(value: T) -> bool;
}

fn keep<T>(value: T) -> T where T: Boxed<T> {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
trait Boxed<T> {
    fn check(value: T) -> bool;
}

impl Boxed<i32> for i32 {
    fn check(value: i32) -> bool {
        return true;
    }
}

impl Boxed<i32> for i32 {
    fn check(value: i32) -> bool {
        return false;
    }
}

fn keep<T>(value: T) -> T where T: Boxed<T> {
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
fn type_checker_enforces_two_arg_called_trait_where_clauses_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait Rel<T, U> {
    fn check(left: T, right: U) -> bool;
}

impl Rel<i32, bool> for i32 {
    fn check(left: i32, right: bool) -> bool {
        return right;
    }
}

fn keep<T, U>(left: T, right: U) -> T where T: Rel<T, U> {
    return left;
}

fn main() {
    let value: i32 = keep(1, true);
    return value;
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
trait Rel<T, U> {
    fn check(left: T, right: U) -> bool;
}

impl Rel<i32, i32> for i32 {
    fn check(left: i32, right: i32) -> bool {
        return true;
    }
}

fn keep<T, U>(left: T, right: U) -> T where T: Rel<T, U> {
    return left;
}

fn main() {
    let value: i32 = keep(1, true);
    return value;
}
"#,
    );
}

#[test]
fn type_checker_rejects_where_clause_subjects_outside_generic_params_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
trait Boxed<T> {
    fn check(value: T) -> bool;
}

fn keep<T>(value: T) -> T where U: Boxed<T> {
    return value;
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_for_loops_with_gpu_iterator_scope() {
    assert_gpu_type_check_ok(
        r#"
fn main(values: [i32]) {
    for value in values {
        let copied: i32 = value;
        continue;
    }
    return 0;
}
"#,
    );

    assert_gpu_type_check_ok(
        r#"
fn main(values: [i32]) {
    for value in values {
        if (value == 2) {
            continue;
        }
    }
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_bounded_match_result_types_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
fn main() -> i32 {
    return match (0) {
        _ -> 1
    };
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
fn main() -> i32 {
    return match (0) {
        _ -> true
    };
}
"#,
    );
}

#[test]
fn type_checker_accepts_generic_enum_match_payloads_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
enum Option<T> {
    Some(T),
    None,
}

fn is_some<T>(value: Option<T>) -> bool {
    return match (value) {
        Some(inner) -> true,
        None -> false,
    };
}

fn unwrap_or<T>(value: Option<T>, fallback: T) -> T {
    return match (value) {
        Some(inner) -> inner,
        None -> fallback,
    };
}
"#,
    );
}
