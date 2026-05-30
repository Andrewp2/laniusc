use laniusc::compiler::CompileError;

use super::{
    assert_gpu_type_check_diagnostic,
    assert_gpu_type_check_ok,
    assert_gpu_type_check_pack_diagnostic,
    assert_gpu_type_check_pack_ok,
    assert_gpu_type_check_pack_rejects,
    assert_gpu_type_check_rejects,
};

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
    assert_gpu_type_check_diagnostic(
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
        "LNC0007",
        &[
            "error[LNC0007]: unknown type",
            "impl Eq<Target> for Target {",
            "type not found",
            "declare the type before using it or import its defining module",
        ],
    );
}

#[test]
fn type_checker_rejects_trait_impls_missing_required_methods_on_gpu() {
    assert_gpu_type_check_diagnostic(
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
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Eq<Target> for Target {",
            "trait impl is missing a required method",
            "implement every method declared by the resolved trait",
        ],
    );
}

#[test]
fn type_checker_rejects_missing_trait_impl_method_even_when_another_impl_defines_it_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Reads<T> {
    fn read(value: T) -> i32;
}

struct Left {
    value: i32,
}

struct Right {
    value: i32,
}

impl Reads<Left> for Left {
}

impl Reads<Right> for Right {
    fn read(value: Right) -> i32 {
        return value.value;
    }
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Reads<Left> for Left {",
            "trait impl is missing a required method",
            "implement every method declared by the resolved trait",
        ],
    );
}

#[test]
fn type_checker_rejects_trait_impl_return_mismatch_even_when_another_impl_matches_name_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Reads<T> {
    fn read(value: T) -> i32;
}

struct Left {
    value: i32,
}

struct Right {
    value: i32,
}

impl Reads<Left> for Left {
    fn read(value: Left) -> bool {
        return value.value > 0;
    }
}

impl Reads<Right> for Right {
    fn read(value: Right) -> i32 {
        return value.value;
    }
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Reads<Left> for Left {",
            "trait impl method signature does not match the trait declaration",
            "match each implemented method's parameter and return types",
        ],
    );
}

#[test]
fn type_checker_rejects_trait_impl_methods_not_declared_by_trait_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Measure<T> {
    fn read(value: T) -> i32;
}

impl Measure<i32> for i32 {
    fn read(value: i32) -> i32 {
        return value;
    }

    fn reset(value: i32) -> i32 {
        return 0;
    }
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Measure<i32> for i32 {",
            "trait impl method signature does not match the trait declaration",
        ],
    );
}

#[test]
fn type_checker_rejects_trait_impls_missing_public_required_methods_on_gpu() {
    assert_gpu_type_check_pack_diagnostic(
        &[
            r#"
module core::describe;

pub trait Describe<T> {
    pub fn describe(value: T) -> i32;
}

pub impl Describe<i32> for i32 {
}
"#,
            r#"
module app;

fn main() {
    return 0;
}
"#,
        ],
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "pub impl Describe<i32> for i32 {",
            "trait impl is missing a required method",
            "implement every method declared by the resolved trait",
        ],
    );
}

#[test]
fn type_checker_rejects_private_impl_method_for_public_trait_contract_on_gpu() {
    assert_gpu_type_check_pack_ok(&[
        r#"
module core::describe;

pub trait Describe<T> {
    pub fn describe(value: T) -> i32;
}

pub impl Describe<i32> for i32 {
    pub fn describe(value: i32) -> i32 {
        return value;
    }
}
"#,
        r#"
module app;

import core::describe;

fn keep<T>(value: T) -> T where T: Describe<T> {
    return value;
}

fn main() {
    let value: i32 = keep(1);
    return value;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::describe;

pub trait Describe<T> {
    pub fn describe(value: T) -> i32;
}

pub impl Describe<i32> for i32 {
    fn describe(value: i32) -> i32 {
        return value;
    }
}
"#,
        r#"
module app;

import core::describe;

fn keep<T>(value: T) -> T where T: Describe<T> {
    return value;
}

fn main() {
    let value: i32 = keep(1);
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_non_public_impl_header_for_public_trait_contract_on_gpu() {
    assert_gpu_type_check_pack_ok(&[
        r#"
module core::describe;

pub trait Describe<T> {
    pub fn describe(value: T) -> i32;
}

pub impl Describe<i32> for i32 {
    pub fn describe(value: i32) -> i32 {
        return value;
    }
}
"#,
        r#"
module app;

import core::describe;

fn keep<T>(value: T) -> T where T: Describe<T> {
    return value;
}

fn main() {
    let value: i32 = keep(1);
    return value;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::describe;

pub trait Describe<T> {
    pub fn describe(value: T) -> i32;
}

impl Describe<i32> for i32 {
    pub fn describe(value: i32) -> i32 {
        return value;
    }
}
"#,
        r#"
module app;

import core::describe;

fn keep<T>(value: T) -> T where T: Describe<T> {
    return value;
}

fn main() {
    let value: i32 = keep(1);
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_public_impl_header_for_private_trait_contract_on_gpu() {
    assert_gpu_type_check_pack_ok(&[r#"
module core::secret;

trait Hidden<T> {
    fn hide(value: T) -> T;
}

impl Hidden<i32> for i32 {
    fn hide(value: i32) -> i32 {
        return value;
    }
}

fn keep<T>(value: T) -> T where T: Hidden<T> {
    return value;
}

fn main() {
    let value: i32 = keep(1);
    return value;
}
"#]);

    assert_gpu_type_check_pack_rejects(&[r#"
module core::secret;

trait Hidden<T> {
    fn hide(value: T) -> T;
}

pub impl Hidden<i32> for i32 {
    fn hide(value: i32) -> i32 {
        return value;
    }
}

fn main() {
    return 0;
}
"#]);
}

#[test]
fn type_checker_rejects_trait_impl_methods_with_wrong_arity_on_gpu() {
    assert_gpu_type_check_diagnostic(
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
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Eq<Target> for Target {",
            "trait impl method has the wrong number of parameters",
            "match each implemented method's parameter list to the trait declaration",
        ],
    );
}

#[test]
fn type_checker_rejects_trait_impl_methods_with_wrong_parameter_type_on_gpu() {
    assert_gpu_type_check_diagnostic(
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
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Eq<Target> for Target {",
            "trait impl method signature does not match the trait declaration",
            "match each implemented method's parameter and return types",
        ],
    );
}

#[test]
fn type_checker_rejects_trait_impl_methods_with_wrong_return_type_on_gpu() {
    assert_gpu_type_check_diagnostic(
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
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Measure<Target> for Target {",
            "trait impl method signature does not match the trait declaration",
            "match each implemented method's parameter and return types",
        ],
    );
}

#[test]
fn type_checker_rejects_later_trait_method_signature_mismatch_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Ops<T> {
    fn first(value: T) -> i32;
    fn second(value: T) -> bool;
}

impl Ops<i32> for i32 {
    fn first(value: i32) -> i32 {
        return value;
    }

    fn second(value: i32) -> i32 {
        return value;
    }
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Ops<i32> for i32 {",
            "trait impl method signature does not match the trait declaration",
            "match each implemented method's parameter and return types",
        ],
    );
}

#[test]
fn type_checker_accepts_reordered_trait_impl_methods_by_owner_name_records() {
    assert_gpu_type_check_ok(
        r#"
trait Ops<T> {
    fn first(value: T) -> i32;
    fn second(value: T) -> bool;
}

impl Ops<i32> for i32 {
    fn second(value: i32) -> bool {
        return value > 0;
    }

    fn first(value: i32) -> i32 {
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
fn type_checker_rejects_trait_impl_method_sets_beyond_gpu_record_window() {
    let trait_methods = (0..33)
        .map(|i| format!("    fn method_{i}(value: T) -> T;"))
        .collect::<Vec<_>>()
        .join("\n");
    let impl_methods = (0..33)
        .map(|i| {
            format!(
                r#"    fn method_{i}(value: i32) -> i32 {{
        return value;
    }}"#
            )
        })
        .collect::<Vec<_>>()
        .join("\n\n");
    let src = format!(
        r#"
trait Wide<T> {{
{trait_methods}
}}

impl Wide<i32> for i32 {{
{impl_methods}
}}

fn main() {{
    return 0;
}}
"#
    );

    assert_gpu_type_check_rejects(&src);
}

#[test]
fn type_checker_rejects_trait_impl_method_where_clauses_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Factory<T> {
    fn make(value: T) -> T;
}

impl Factory<i32> for i32 {
    fn make(value: i32) -> i32 where i32: Factory<i32> {
        return value;
    }
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "fn make(value: i32) -> i32 where i32: Factory<i32> {",
            "trait method where clauses are outside the current GPU trait contract records",
            "method-level predicate solving is implemented on GPU",
        ],
    );
}

#[test]
fn type_checker_reports_trait_method_where_on_trait_declaration() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Factory {
    fn make(value: i32) -> i32 where i32: Factory;
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "fn make(value: i32) -> i32 where i32: Factory;",
            "trait method where clauses are outside the current GPU trait contract records",
            "method-level predicate solving is implemented on GPU",
        ],
    );
}

#[test]
fn type_checker_rejects_duplicate_trait_method_contracts_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Eq<T> {
    fn same(left: T, right: T) -> bool;
    fn same(value: T) -> bool;
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "fn same(value: T) -> bool;",
            "trait declares duplicate method contracts",
            "GPU trait method overload resolution is implemented",
        ],
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
fn type_checker_rejects_trait_impl_method_level_generics_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Factory {
    fn make<T>(value: T) -> T;
}

impl Factory for i32 {
    fn make<T>(value: T) -> T {
        return value;
    }
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "fn make<T>(value: T) -> T;",
            "trait method-level generics are outside the current GPU trait contract records",
            "method-level generic substitution is implemented on GPU",
        ],
    );
}

#[test]
fn type_checker_rejects_trait_header_arity_mismatches_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Pair<Left, Right> {
    fn check(value: i32) -> bool;
}

impl Pair<i32> for i32 {
    fn check(value: i32) -> bool {
        return true;
    }
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Pair<i32> for i32 {",
            "trait impl header uses the wrong number of trait arguments",
        ],
    );

    assert_gpu_type_check_diagnostic(
        r#"
trait Marker {
    fn check(value: i32) -> bool;
}

fn keep<T>(value: T) -> T where T: Marker<i32> {
    return value;
}

fn main() {
    return 0;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "fn keep<T>(value: T) -> T where T: Marker<i32> {",
            "trait bound uses the wrong number of trait arguments",
        ],
    );
}

#[test]
fn type_checker_rejects_unresolved_trait_impl_argument_types_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Rel<T> {
}

impl Rel<Missing> for i32 {
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Rel<Missing> for i32 {",
            "trait impl header contains an unknown trait argument type",
        ],
    );
}

#[test]
fn type_checker_rejects_trait_impl_targets_that_resolve_to_traits_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Marker {
}

trait Target {
}

impl Marker for Target {
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "trait impl target type is outside the current GPU predicate row shape",
        ],
    );
}

#[test]
fn type_checker_rejects_generic_trait_impl_targets_until_target_args_are_recorded_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

trait Marker {
    fn check(value: i32) -> bool;
}

impl Marker for Boxed<i32> {
    fn check(value: i32) -> bool {
        return true;
    }
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "trait impl target type is outside the current GPU predicate row shape",
            "trait impl predicate rows currently match only scalar and non-generic nominal targets",
        ],
    );
}

#[test]
fn type_checker_rejects_trait_impl_targets_aliasing_type_instances_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
type Four = [i32; 4];

trait Marker {
}

impl Marker for Four {
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "trait impl target type is outside the current GPU predicate row shape",
            "trait impl predicate rows currently match only scalar and non-generic nominal targets",
        ],
    );
}

#[test]
fn type_checker_rejects_trait_method_dispatch_until_gpu_lookup_supports_it() {
    let err = crate::common::type_check_source_with_timeout(
        r#"
trait Describe<T> {
    fn describe(value: T) -> i32;
}

impl Describe<i32> for i32 {
    fn describe(value: i32) -> i32 {
        return value;
    }
}

fn main() {
    let value: i32 = 7;
    return value.describe();
}
"#,
    )
    .expect_err("trait impl methods should not be available through inherent method dispatch");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0027");
            assert_eq!(diagnostic.message, "call resolution failed");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("method dispatch rejection should point at the method name");
            assert_eq!(
                label.message,
                "call does not match a resolved function or method"
            );
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("supported function or method signature")),
                "diagnostic should describe unsupported callable lookup: {diagnostic:?}"
            );
        }
        other => panic!("expected stable method dispatch diagnostic, got {other:?}"),
    }
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

fn seed() -> i32 {
    return 7;
}

fn keep<T>(value: T) -> T where T: Boxed<T> {
    return value;
}

fn main() {
    let value: i32 = keep(seed());
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
fn type_checker_rejects_trait_bound_argument_paths_beyond_gpu_scan_window() {
    let long_arg_path = (0..70)
        .map(|i| format!("module_{i}"))
        .collect::<Vec<_>>()
        .join("::");
    let source = format!(
        r#"
trait Rel<T> {{
}}

fn keep<T>(value: T) -> T where T: Rel<{long_arg_path}> {{
    return value;
}}

fn main() {{
    let value: i32 = keep(1);
    return value;
}}
"#,
    );

    assert_gpu_type_check_diagnostic(
        &source,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "trait bound argument shape is not supported by the current GPU predicate row",
            "predicate rows currently store scalar, generic, or concrete declaration leaves",
        ],
    );
}

#[test]
fn type_checker_rejects_declaration_trait_bounds_until_instantiation_obligations_exist_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Marker<T> {
}

impl Marker<i32> for i32 {
}

struct Boxed<T: Marker<T> > {
    value: T,
}

fn main() {
    let value: Boxed<i32> = Boxed { value: 1 };
    return value.value;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "struct Boxed<T: Marker<T> > {",
            "trait bounds on this generic declaration are not enforced by the current GPU predicate solver",
            "GPU instantiation obligation rows",
        ],
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
