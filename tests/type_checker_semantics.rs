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
fn type_checker_accepts_concrete_generic_struct_instances() {
    // Generic struct declarations remain unsupported in generic form, but concrete
    // generic instances must be accepted once token consumers can use the
    // resolved member/type metadata from the instance passes.
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
fn type_checker_rejects_generic_bounds_until_gpu_predicate_semantics_exist() {
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
    return 0;
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
    assert_gpu_type_check_rejects(
        r#"
fn bad_call<T, const N: usize>(values: [T; N]) -> T {
    return values[0];
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    return bad_call(values);
}
"#,
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
fn type_checker_rejects_generic_enum_constructor_returns_until_gpu_substitution_exists() {
    assert_gpu_type_check_rejects(
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
fn type_checker_rejects_array_returns_outside_bounded_gpu_slice() {
    assert_gpu_type_check_rejects(
        r#"
fn filled(value: i32) -> [i32; 4] {
    return [value, value, value, value];
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
fn copy_generic<T, const N: usize>(values: [T; N]) -> [T; N] {
    return values;
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
fn type_checker_rejects_traits_until_gpu_trait_semantics_exist() {
    assert_gpu_type_check_rejects(
        r#"
trait Eq {
    fn eq(left: i32, right: i32) -> bool;
}

fn main() {
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
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
fn type_checker_rejects_where_clauses_until_gpu_predicate_semantics_exist() {
    assert_gpu_type_check_rejects(
        r#"
struct Boxed<T> {
    value: T,
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
}

#[test]
fn type_checker_rejects_match_until_gpu_match_semantics_exist() {
    assert_gpu_type_check_rejects(
        r#"
fn main() {
    let value: i32 = match (0) {
        _ -> 1
    };
    return value;
}
"#,
    );
}
