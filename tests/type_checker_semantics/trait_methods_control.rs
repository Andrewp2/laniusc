use laniusc_compiler::compiler::CompileError;

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
fn type_checker_rejects_inherent_method_level_generics_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed {
    value: i32,
}

impl Boxed {
    fn wrap<T>(value: T) -> T {
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
            "fn wrap<T>(value: T) -> T {",
            "trait method-level generics are outside the current GPU trait contract records",
        ],
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
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Eq<Target> for Target {",
            "trait impl header does not resolve to a trait",
            "name a trait in the impl header before providing trait methods",
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
}

impl Measure<i32> for i32 {
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
            "fn reset(value: i32) -> i32 {",
            "trait impl declares a method not required by the trait",
            "remove extra impl methods or declare the method in the resolved trait contract",
        ],
    );
}

#[test]
fn type_checker_reports_malformed_extra_impl_method_contract_status_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Marker {
}

impl Marker for i32 {
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
            "fn make<T>(value: T) -> T {",
            "trait method-level generics are outside the current GPU trait contract records",
            "move the generic parameter to the trait or impl receiver type",
        ],
    );
}

#[test]
fn type_checker_rejects_required_trait_impl_method_level_generics_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Factory<T> {
    fn make(value: T) -> T;
}

impl Factory<i32> for i32 {
    fn make<U>(value: i32) -> i32 {
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
            "fn make<U>(value: i32) -> i32 {",
            "trait method-level generics are outside the current GPU trait contract records",
            "move the generic parameter to the trait or impl receiver type",
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

    assert_gpu_type_check_pack_diagnostic(
        &[
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
        ],
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "fn describe(value: i32) -> i32 {",
            "trait impl method visibility does not match the trait declaration",
            "match each impl method's visibility to the resolved trait method contract",
        ],
    );
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
fn type_checker_rejects_private_impl_header_for_public_marker_trait_on_gpu() {
    assert_gpu_type_check_pack_ok(&[
        r#"
module core::marker;

pub trait Marker<T> {
}

pub impl Marker<i32> for i32 {
}
"#,
        r#"
module app;

import core::marker;

fn keep<T>(value: T) -> T where T: Marker<T> {
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
module core::marker;

pub trait Marker<T> {
}

impl Marker<i32> for i32 {
}
"#,
        r#"
module app;

import core::marker;

fn keep<T>(value: T) -> T where T: Marker<T> {
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
}

impl Hidden<i32> for i32 {
}

fn main() {
    return 0;
}
"#]);

    assert_gpu_type_check_pack_diagnostic(
        &[r#"
module core::secret;

trait Hidden<T> {
}

pub impl Hidden<i32> for i32 {
}

fn main() {
    return 0;
}
"#],
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "trait impl visibility does not match the resolved trait contract",
            "public trait impls and public traits must agree",
        ],
    );
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
fn type_checker_accepts_trait_impl_method_sets_beyond_old_record_window() {
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

    assert_gpu_type_check_ok(&src);
}

#[test]
fn type_checker_reports_missing_trait_impl_method_beyond_old_record_window() {
    let trait_methods = (0..33)
        .map(|i| format!("    fn method_{i}(value: T) -> T;"))
        .collect::<Vec<_>>()
        .join("\n");
    let impl_methods = (0..32)
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

    assert_gpu_type_check_diagnostic(
        &src,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Wide<i32> for i32 {",
            "trait impl is missing a required method",
            "implement every method declared by the resolved trait",
        ],
    );
}

#[test]
fn type_checker_reports_extra_trait_impl_method_beyond_old_record_window() {
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

    fn extra_method(value: i32) -> i32 {{
        return value;
    }}
}}

fn main() {{
    return 0;
}}
"#
    );

    assert_gpu_type_check_diagnostic(
        &src,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "fn extra_method(value: i32) -> i32 {",
            "trait impl declares a method not required by the trait",
            "remove extra impl methods or declare the method in the resolved trait contract",
        ],
    );
}

#[test]
fn type_checker_reports_trait_impl_arity_mismatch_beyond_old_record_window() {
    let trait_methods = (0..33)
        .map(|i| format!("    fn method_{i}(value: T) -> T;"))
        .collect::<Vec<_>>()
        .join("\n");
    let impl_methods = (0..33)
        .map(|i| {
            if i == 32 {
                format!(
                    r#"    fn method_{i}(value: i32, extra: i32) -> i32 {{
        return value + extra;
    }}"#
                )
            } else {
                format!(
                    r#"    fn method_{i}(value: i32) -> i32 {{
        return value;
    }}"#
                )
            }
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

    assert_gpu_type_check_diagnostic(
        &src,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Wide<i32> for i32 {",
            "trait impl method has the wrong number of parameters",
            "match each implemented method's parameter list to the trait declaration",
        ],
    );
}

#[test]
fn type_checker_reports_late_trait_method_generic_contract_beyond_old_record_window() {
    let trait_methods = (0..33)
        .map(|i| {
            if i == 32 {
                "    fn method_32<U>(value: T, extra: U) -> T;".to_owned()
            } else {
                format!("    fn method_{i}(value: T) -> T;")
            }
        })
        .collect::<Vec<_>>()
        .join("\n");
    let impl_methods = (0..33)
        .map(|i| {
            if i == 32 {
                r#"    fn method_32(value: i32, extra: i32) -> i32 {
        return value + extra;
    }"#
                .to_owned()
            } else {
                format!(
                    r#"    fn method_{i}(value: i32) -> i32 {{
        return value;
    }}"#
                )
            }
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

    assert_gpu_type_check_diagnostic(
        &src,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "trait method-level generics are outside the current GPU trait contract records",
            "move the generic parameter to the trait or impl receiver type",
        ],
    );
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
            "move the bound to the trait, impl, or caller-visible where clause",
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
            "move the bound to the trait, impl, or caller-visible where clause",
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
fn type_checker_rejects_overwide_generic_instance_parameters_until_rows_carry_all_args() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Wide<A, B, C, D, E, F, G, H, I> {
    value: A,
}

trait TakeWide {
    fn take(value: Wide<i32, i32, i32, i32, i32, i32, i32, i32, i32>) -> i32;
}

struct Target {
    value: i32,
}

impl TakeWide for Target {
    fn take(value: Wide<i32, i32, i32, i32, i32, i32, i32, i32, bool>) -> i32 {
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
            "fn take(value: Wide<i32, i32, i32, i32, i32, i32, i32, i32, i32>) -> i32;",
            "trait impl method signature does not match the trait declaration",
            "match each implemented method's parameter and return types",
        ],
    );
}

#[test]
fn type_checker_rejects_nested_trait_method_generic_instances_without_partial_match() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

struct Maybe<T> {
    value: T,
}

trait ReadNested<T> {
    fn read(value: Maybe<Boxed<T>>) -> T;
}

struct Target {
    value: i32,
}

impl ReadNested<i32> for Target {
    fn read(value: Maybe<Boxed<i32>>) -> i32 {
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
            "fn read(value: Maybe<Boxed<T>>) -> T;",
            "trait impl method signature does not match the trait declaration",
            "nested generic instance parameters are rejected for now rather than partially matched",
        ],
    );
}

#[test]
fn type_checker_rejects_nested_trait_method_generic_instance_returns_without_partial_match() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

struct Maybe<T> {
    value: T,
}

trait WrapNested<T> {
    fn wrap(value: T) -> Maybe<Boxed<T>>;
}

struct Target {
    value: i32,
}

impl WrapNested<i32> for Target {
    fn wrap(value: i32) -> Maybe<Boxed<i32>> {
        return Maybe { value: Boxed { value: value } };
    }
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "fn wrap(value: T) -> Maybe<Boxed<T>>;",
            "trait impl method signature does not match the trait declaration",
            "nested generic instance parameters are rejected for now rather than partially matched",
        ],
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
fn type_checker_reports_unsupported_trait_impl_argument_shapes_as_impl_diagnostics_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Wide<Left, Middle, Right> {
}

impl Wide<i32, bool, i32> for i32 {
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Wide<i32, bool, i32> for i32 {",
            "trait impl header exceeds the current GPU predicate argument limit",
            "records at most two trait type arguments per trait impl row",
        ],
    );

    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

trait Rel<T> {
}

impl Rel<Boxed<i32>> for i32 {
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Rel<Boxed<i32>> for i32 {",
            "trait impl header uses an unsupported trait argument shape",
            "nested generic arguments are rejected rather than matching only the outer type name",
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
fn type_checker_rejects_generic_trait_impl_arguments_until_predicate_rows_carry_param_refs_on_gpu()
{
    assert_gpu_type_check_diagnostic(
        r#"
struct T {
    value: i32,
}

trait Rel<Value> {
}

impl<T> Rel<T> for i32 {
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl<T> Rel<T> for i32 {",
            "trait impl header uses generic trait arguments outside the current GPU predicate row shape",
            "publish trait impl argument rows that carry generic-parameter references",
        ],
    );
}

#[test]
fn type_checker_rejects_unresolved_trait_impl_targets_with_stable_diagnostic() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Marker {
}

impl Marker for Missing {
}

fn main() {
    return 0;
}
"#,
        "LNC0007",
        &[
            "error[LNC0007]: unknown type",
            "impl Marker for Missing {",
            "type not found",
            "declare the type before using it or import its defining module",
        ],
    );
}

#[test]
fn type_checker_rejects_reference_trait_impl_targets_with_stable_diagnostic() {
    let err = crate::common::type_check_source_with_timeout(
        r#"
trait Marker {
}

impl Marker for &i32 {
}

fn main() {
    return 0;
}
"#,
    )
    .expect_err("reference trait-impl targets should fail GPU predicate validation");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0021");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("diagnostic should identify the unsupported target type");
            assert_eq!(label.source_line.as_deref(), Some("impl Marker for &i32 {"));
            assert_eq!(label.column, 1);
            assert_eq!(label.length, 4);

            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0021]: invalid trait implementation"));
            assert!(rendered
                .contains("trait impl target type is outside the current GPU predicate row shape"));
        }
        other => panic!("expected reference trait impl target diagnostic, got {other:?}"),
    }
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
            "impl Marker for Target {",
        ],
    );
}

#[test]
fn type_checker_rejects_inherent_impls_on_traits_with_trait_impl_diagnostic() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Marker {
}

impl Marker {
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
            "impl Marker {",
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
            "impl Marker for Boxed<i32> {",
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
            "impl Marker for Four {",
        ],
    );
}

#[test]
fn type_checker_rejects_trait_impl_targets_aliasing_scalar_types_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
type Count = i32;

trait Marker {
}

impl Marker for Count {
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Marker for Count {",
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
fn type_checker_rejects_trait_impl_methods_as_free_functions_until_dispatch_rows_exist() {
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
    return describe(7);
}
"#,
    )
    .expect_err("trait impl methods should not enter the free-function namespace");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0027");
            assert_eq!(diagnostic.message, "call resolution failed");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("free-function rejection should point at the call");
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
        other => panic!("expected stable free-function call diagnostic, got {other:?}"),
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
fn type_checker_enforces_imported_generic_trait_where_clauses_on_gpu() {
    let contracts = r#"
module contracts::cmp;

pub trait Eq<T> {
    pub fn eq(left: T, right: T) -> bool;
}

pub impl Eq<i32> for i32 {
    pub fn eq(left: i32, right: i32) -> bool {
        return left == right;
    }
}
"#;

    let guards = r#"
module contracts::guards;

import contracts::cmp;

pub fn keep<T>(value: T) -> T {
    return value;
}

pub fn require_eq<T>(value: T) -> T where T: contracts::cmp::Eq<T> {
    return keep(value);
}
"#;

    assert_gpu_type_check_pack_ok(&[
        contracts,
        guards,
        r#"
module app;

import contracts::cmp;
import contracts::guards;

fn main() {
    let value: i32 = contracts::guards::require_eq(contracts::guards::keep(7));
    return value;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        contracts,
        guards,
        r#"
module app;

import contracts::cmp;
import contracts::guards;

fn main() {
    let value: bool = contracts::guards::require_eq(true);
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_enforces_imported_nonzero_slot_trait_where_clauses_on_gpu() {
    let contracts = r#"
module contracts::cmp;

pub trait Eq<T> {
    pub fn eq(left: T, right: T) -> bool;
}

pub impl Eq<i32> for i32 {
    pub fn eq(left: i32, right: i32) -> bool {
        return left == right;
    }
}
"#;

    let guards = r#"
module contracts::guards;

import contracts::cmp;

pub fn keep<T>(value: T) -> T {
    return value;
}

pub fn require_right<T, U>(left: T, right: U) -> U where U: contracts::cmp::Eq<U> {
    return keep(right);
}
"#;

    assert_gpu_type_check_pack_ok(&[
        contracts,
        guards,
        r#"
module app;

import contracts::cmp;
import contracts::guards;

fn main() {
    let value: i32 = contracts::guards::require_right(false, 7);
    return value;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        contracts,
        guards,
        r#"
module app;

import contracts::cmp;
import contracts::guards;

fn main() {
    let value: bool = contracts::guards::require_right(1, true);
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_unresolved_long_trait_impl_target_paths() {
    let target_path = (0..9)
        .map(|i| format!("module_{i}"))
        .chain(std::iter::once("Target".to_string()))
        .collect::<Vec<_>>()
        .join("::");
    let src = format!(
        r#"
trait Marker {{
}}

impl Marker for {target_path} {{
}}

fn main() {{
    return 0;
}}
"#
    );

    assert_gpu_type_check_diagnostic(
        &src,
        "LNC0007",
        &[
            "error[LNC0007]: unknown type",
            "impl Marker for module_0::module_1::module_2::module_3::module_4::module_5::module_6::module_7::module_8::Target {",
            "type not found",
            "declare the type before using it or import its defining module",
        ],
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
fn type_checker_rejects_trait_bound_argument_paths_beyond_predicate_row_width() {
    let source = r#"
trait Rel<T> {
}

fn keep<T>(value: T) -> T where T: Rel<a::b::c::d::e::f::g::h::i::j> {
    return value;
}
"#;

    let err = super::common::type_check_source_with_timeout(source)
        .expect_err("over-wide bound argument paths should fail predicate validation");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0008");
            let rendered = diagnostic.render();
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("diagnostic should point at the over-wide bound argument");
            let source_line =
                "fn keep<T>(value: T) -> T where T: Rel<a::b::c::d::e::f::g::h::i::j> {";
            assert_eq!(label.source_line.as_deref(), Some(source_line));
            assert_eq!(
                label.column,
                source_line.find("i::j").unwrap() + 1,
                "{rendered}"
            );
            assert_eq!(label.length, "i".len());

            assert!(rendered.contains("error[LNC0008]: unsatisfied trait bound"));
            assert!(
                rendered.contains("trait bound path exceeds the current GPU predicate path limit")
            );
        }
        other => panic!("expected over-wide bound argument diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_rejects_trait_bound_target_paths_beyond_predicate_row_width() {
    let source = r#"
fn keep<T>(value: T) -> T where T: a::b::c::d::e::f::g::h::i::j {
    return value;
}
"#;

    let err = super::common::type_check_source_with_timeout(source)
        .expect_err("over-wide bound target paths should fail predicate validation");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0008");
            let rendered = diagnostic.render();
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("diagnostic should point at the over-wide bound target");
            let source_line = "fn keep<T>(value: T) -> T where T: a::b::c::d::e::f::g::h::i::j {";
            assert_eq!(label.source_line.as_deref(), Some(source_line));
            assert_eq!(
                label.column,
                source_line.find("i::j").unwrap() + 1,
                "{rendered}"
            );
            assert_eq!(label.length, "i".len());

            assert!(rendered.contains("error[LNC0008]: unsatisfied trait bound"));
            assert!(
                rendered.contains("trait bound path exceeds the current GPU predicate path limit")
            );
        }
        other => panic!("expected over-wide bound target diagnostic, got {other:?}"),
    }
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
