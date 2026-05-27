use super::{assert_gpu_type_check_ok, assert_gpu_type_check_rejects};

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
    let range: Range<i32> = Range { start: 1, end: 4 };
    return read(range);
}
"#,
    );

    assert_gpu_type_check_rejects(
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
    );

    assert_gpu_type_check_rejects(
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

fn main() {
    let left: Option<i32> = Some(1);
    let right: Option<i32> = None;
    let flag: bool = is_some(left);
    let value: i32 = unwrap_or(right, 2);
    if (flag) {
        return value;
    }
    return 0;
}
"#,
    );
}
