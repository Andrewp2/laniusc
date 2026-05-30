mod common;

use laniusc::compiler::CompileError;

fn assert_gpu_type_check_ok(src: &str) {
    common::type_check_source_with_timeout(src).expect("source should pass GPU type checking");
}

fn assert_gpu_type_check_rejects(src: &str) {
    match common::type_check_source_with_timeout(src) {
        Ok(()) => panic!("source should fail GPU type checking"),
        Err(CompileError::Diagnostic(_)) => {}
        Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type check error, got {other:?}"),
    }
}

fn assert_gpu_type_check_pack_ok(sources: &[&str]) {
    common::type_check_source_pack_with_timeout(sources)
        .expect("source pack should pass GPU type checking");
}

fn assert_gpu_type_check_pack_rejects(sources: &[&str]) {
    match common::type_check_source_pack_with_timeout(sources) {
        Ok(()) => panic!("source pack should fail GPU type checking"),
        Err(CompileError::Diagnostic(_)) => {}
        Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type check error, got {other:?}"),
    }
}

fn assert_gpu_type_check_diagnostic(src: &str, expected_code: &str, expected_fragments: &[&str]) {
    let err = common::type_check_source_with_timeout(src)
        .expect_err("source should fail GPU type checking");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, expected_code);
            let rendered = diagnostic.render();
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

fn assert_gpu_type_check_pack_diagnostic(
    sources: &[&str],
    expected_code: &str,
    expected_fragments: &[&str],
) {
    let err = common::type_check_source_pack_with_timeout(sources)
        .expect_err("source pack should fail GPU type checking");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, expected_code);
            let rendered = diagnostic.render();
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
fn type_checker_assignment_mismatch_reports_stable_diagnostic() {
    let src = r#"
fn main() {
    let value: i32 = false;
    return 0;
}
"#;

    let err = common::type_check_source_with_timeout(src)
        .expect_err("assignment type mismatch should fail GPU type checking");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0006");
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0006]: type mismatch"));
            assert!(rendered.contains("let value: i32 = false;"));
            assert!(rendered.contains("expected a different type here"));
            assert!(rendered.contains("= note:"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        other => panic!("expected assignment mismatch diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_source_pack_reports_scope_and_type_errors_as_diagnostics() {
    let unresolved = common::type_check_source_pack_with_timeout(&[
        r#"
module core::ok;

pub fn one() -> i32 {
    return 1;
}
"#,
        r#"
module app;

fn main() {
    let value: i32 = missing_value;
    return value;
}
"#,
    ])
    .expect_err("source-pack unresolved identifier should fail GPU type checking");

    match unresolved {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0005");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("diagnostic should identify the source-pack token");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    let value: i32 = missing_value;")
            );
            let rendered = diagnostic.render();
            assert!(rendered.contains("not found in this scope"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        other => panic!("expected unresolved identifier diagnostic, got {other:?}"),
    }

    let unknown_type = common::type_check_source_pack_with_timeout(&[
        r#"
module core::ok;

pub fn one() -> i32 {
    return 1;
}
"#,
        r#"
module app;

fn keep<T>(value: T) -> T where T: MissingTrait<T> {
    return value;
}

fn main() {
    let value: i32 = keep(1);
    return value;
}
"#,
    ])
    .expect_err("source-pack unknown type should fail GPU type checking");

    match unknown_type {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0007");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("diagnostic should identify the source-pack token");
            assert_eq!(
                label.source_line.as_deref(),
                Some("fn keep<T>(value: T) -> T where T: MissingTrait<T> {")
            );
            let rendered = diagnostic.render();
            assert!(rendered.contains("type not found"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        other => panic!("expected unknown type diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_accepts_generated_let_chain_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
fn main() {
    let generated_seed: i32 = 1;
    let generated_step: i32 = generated_seed + 2;
    let generated_total: i32 = generated_step + generated_seed;
    let generated_guard: bool = generated_total == 4;
    if (generated_guard) {
        return generated_total;
    }
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_generated_call_argument_shapes_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
fn generated_add(generated_left: i32, generated_right: i32) -> i32 {
    return generated_left + generated_right;
}

fn generated_keep(generated_value: i32) -> i32 {
    return generated_value;
}

fn generated_choose(generated_flag: bool, generated_left: i32, generated_right: i32) -> i32 {
    if (generated_flag) {
        return generated_left;
    }
    return generated_right;
}

fn main() {
    let generated_seed: i32 = 3;
    return generated_choose(
        generated_seed < 4,
        generated_add(generated_keep(generated_seed), 4),
        generated_add(1, generated_keep(2)),
    );
}
"#,
    );
}

#[test]
fn type_checker_rejects_nonzero_call_argument_type_mismatches_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
fn generated_mix(first: i32, second: bool, third: i32, fourth: bool) -> i32 {
    if (second && fourth) {
        return first;
    }
    return third;
}

fn main() {
    return generated_mix(1, true, false, true);
}
"#,
    );
}

#[test]
fn type_checker_rejects_direct_calls_beyond_gpu_argument_width() {
    assert_gpu_type_check_diagnostic(
        r#"
fn generated_sum(first: i32, second: i32, third: i32, fourth: i32, fifth: i32) -> i32 {
    return first + second + third + fourth + fifth;
}

fn main() {
    return generated_sum(1, 2, 3, 4, 5);
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
fn type_checker_rejects_generic_array_calls_beyond_gpu_argument_width() {
    assert_gpu_type_check_diagnostic(
        r#"
fn copy_wide<T, const N: usize>(
    values: [T; N],
    first: i32,
    second: i32,
    third: i32,
    fourth: i32
) -> [T; N] {
    return values;
}

fn main() {
    let values: [i32; 2] = [1, 2];
    let copied: [i32; 2] = copy_wide(values, 1, 2, 3, 4);
    return copied[0];
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
fn type_checker_rejects_nonzero_generic_call_argument_mismatches_on_gpu() {
    assert_gpu_type_check_rejects(
        r#"
fn generated_same<T>(first: T, second: T) -> T {
    return first;
}

fn main() {
    return generated_same(1, false);
}
"#,
    );
}

#[test]
fn type_checker_rejects_duplicate_generic_parameter_names_before_inference_on_gpu() {
    let cases = [
        r#"
fn choose<T, T>(left: T, right: T) -> T {
    return left;
}

fn main() {
    let value: i32 = choose(1, 2);
    return value;
}
"#,
        r#"
fn first_i32<const N: usize, const N: usize>(values: [i32; N]) -> i32 {
    return values[0];
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    return first_i32(values);
}
"#,
    ];

    for src in cases {
        let err = common::type_check_source_with_timeout(src)
            .expect_err("duplicate generic parameter names should fail GPU type checking");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0033");
                let rendered = diagnostic.render();
                assert!(rendered.contains("invalid generic parameter list"));
                assert!(rendered.contains("generic parameter name is already declared"));
                assert!(!rendered.contains("GPU type check rejected"));
            }
            other => panic!("expected duplicate generic parameter diagnostic, got {other:?}"),
        }
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
fn type_checker_method_calls_use_hir_member_receiver_over_global_name_spelling() {
    assert_gpu_type_check_ok(
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

fn contains(value: bool) -> bool {
    return value;
}

fn make_range() -> Range {
    return Range { start: 1, end: 4 };
}

fn main() {
    if (make_range().contains(2)) {
        return 1;
    }
    return 0;
}
"#,
    );

    let err = common::type_check_source_with_timeout(
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

fn contains(value: bool) -> bool {
    return value;
}

fn make_range() -> Range {
    return Range { start: 1, end: 4 };
}

fn main() {
    if (make_range().contains(false)) {
        return 1;
    }
    return 0;
}
"#,
    )
    .expect_err("method argument type should be checked against the receiver-selected method");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0006");
            let rendered = diagnostic.render();
            assert!(rendered.contains("make_range().contains(false)"));
            assert!(rendered.contains("expected a different type here"));
        }
        other => panic!("expected method argument type diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_resolves_methods_by_concrete_generic_receiver_instance() {
    assert_gpu_type_check_ok(
        r#"
struct NumberBox<T> {
    value: T,
}

struct FlagBox<T> {
    value: T,
}

impl NumberBox<i32> {
    fn read(self) -> i32 {
        return self.value;
    }
}

impl FlagBox<bool> {
    fn read(self) -> bool {
        return self.value;
    }
}

fn main() {
    let number_box: NumberBox<i32> = NumberBox { value: 7 };
    let flag_box: FlagBox<bool> = FlagBox { value: true };
    let number: i32 = number_box.read();
    let flag: bool = flag_box.read();
    if (flag) {
        return number;
    }
    return 0;
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
struct NumberBox<T> {
    value: T,
}

struct FlagBox<T> {
    value: T,
}

impl NumberBox<i32> {
    fn read(self) -> i32 {
        return self.value;
    }
}

impl FlagBox<bool> {
    fn read(self) -> bool {
        return self.value;
    }
}

fn main() {
    let number_box: NumberBox<i32> = NumberBox { value: 7 };
    let wrong: bool = number_box.read();
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_accepts_distinct_methods_on_concrete_generic_receiver_impls() {
    assert_gpu_type_check_ok(
        r#"
struct Boxed<T> {
    value: T,
}

impl Boxed<i32> {
    fn read_number(self) -> i32 {
        return self.value;
    }
}

impl Boxed<bool> {
    fn read_flag(self) -> bool {
        return self.value;
    }
}

fn main() {
    let number_box: Boxed<i32> = Boxed { value: 7 };
    let flag_box: Boxed<bool> = Boxed { value: true };
    let number: i32 = number_box.read_number();
    let flag: bool = flag_box.read_flag();
    if (flag) {
        return number;
    }
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_matches_same_name_methods_by_concrete_generic_receiver_arguments() {
    assert_gpu_type_check_ok(
        r#"
struct Boxed<T> {
    value: T,
}

impl Boxed<i32> {
    fn read(self) -> i32 {
        return self.value;
    }
}

impl Boxed<bool> {
    fn read(self) -> bool {
        return self.value;
    }
}

fn main() {
    let number_box: Boxed<i32> = Boxed { value: 7 };
    let flag_box: Boxed<bool> = Boxed { value: true };
    let number: i32 = number_box.read();
    let flag: bool = flag_box.read();
    if (flag) {
        return number;
    }
    return 0;
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
struct Boxed<T> {
    value: T,
}

impl Boxed<i32> {
    fn read(self) -> i32 {
        return self.value;
    }
}

fn main() {
    let flag_box: Boxed<bool> = Boxed { value: true };
    let wrong: i32 = flag_box.read();
    return wrong;
}
"#,
    );
}

#[test]
fn type_checker_rejects_method_lookup_on_under_applied_generic_receivers() {
    assert_gpu_type_check_rejects(
        r#"
struct PairBox<Left, Right> {
    left: Left,
    right: Right,
}

impl PairBox<i32> {
    fn read(self) -> i32 {
        return 1;
    }
}

extern "host" fn make_pair() -> PairBox<i32>;

fn main() {
    return make_pair().read();
}
"#,
    );
}

#[test]
fn type_checker_resolves_generic_inherent_methods_on_concrete_receivers() {
    assert_gpu_type_check_ok(
        r#"
struct Boxed<T> {
    value: T,
}

impl<T> Boxed<T> {
    fn present(self) -> bool {
        return true;
    }
}

fn main() {
    let number_box: Boxed<i32> = Boxed { value: 7 };
    let flag_box: Boxed<bool> = Boxed { value: false };
    let number_present: bool = number_box.present();
    let flag_present: bool = flag_box.present();
    if (number_present && flag_present) {
        return 1;
    }
    return 0;
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
struct Boxed<T> {
    value: T,
}

impl<T> Boxed<T> {
    fn present(self) -> bool {
        return true;
    }
}

fn main() {
    let number_box: Boxed<i32> = Boxed { value: 7 };
    let wrong: i32 = number_box.present();
    return wrong;
}
"#,
    );
}

#[test]
fn type_checker_rejects_overlapping_exact_and_generic_inherent_methods() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

impl<T> Boxed<T> {
    fn read(self) -> i32 {
        return 0;
    }
}

impl Boxed<i32> {
    fn read(self) -> i32 {
        return self.value;
    }
}

fn main() {
    let number_box: Boxed<i32> = Boxed { value: 7 };
    return number_box.read();
}
"#,
        "LNC0027",
        &[
            "error[LNC0027]: call resolution failed",
            "return number_box.read();",
            "call does not match a resolved function or method",
            "no supported function or method signature matches this receiver and argument list",
        ],
    );
}

#[test]
fn type_checker_reports_generic_inherent_method_returns_outside_bounded_gpu_slice() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

impl<T> Boxed<T> {
    fn read(self) -> T {
        return self.value;
    }
}

fn main() {
    let number_box: Boxed<i32> = Boxed { value: 7 };
    let flag_box: Boxed<bool> = Boxed { value: true };
    let number: i32 = number_box.read();
    let flag: bool = flag_box.read();
    if (flag) {
        return number;
    }
    return 0;
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "let number: i32 = number_box.read();",
            "expected a different type here",
        ],
    );

    assert_gpu_type_check_rejects(
        r#"
struct Boxed<T> {
    value: T,
}

impl<T> Boxed<T> {
    fn read(self) -> T {
        return self.value;
    }
}

fn main() {
    let number_box: Boxed<i32> = Boxed { value: 7 };
    let wrong: bool = number_box.read();
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_matches_methods_by_two_concrete_generic_receiver_arguments_in_source_pack() {
    assert_gpu_type_check_pack_ok(&[
        r#"
module core::pair;

pub struct PairBox<Left, Right> {
    left: Left,
    right: Right,
}

pub impl PairBox<i32, bool> {
    pub fn second(self) -> bool {
        return self.right;
    }
}

pub impl PairBox<i32, i32> {
    pub fn second(self) -> i32 {
        return self.right;
    }
}
"#,
        r#"
module app;

import core::pair;

fn main() {
    let flag_box: PairBox<i32, bool> = PairBox { left: 7, right: true };
    let int_box: PairBox<i32, i32> = PairBox { left: 1, right: 2 };
    let flag: bool = flag_box.second();
    let value: i32 = int_box.second();
    if (flag) {
        return value;
    }
    return 0;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::pair;

pub struct PairBox<Left, Right> {
    left: Left,
    right: Right,
}

pub impl PairBox<i32, bool> {
    pub fn second(self) -> bool {
        return self.right;
    }
}
"#,
        r#"
module app;

import core::pair;

fn main() {
    let int_box: PairBox<i32, i32> = PairBox { left: 1, right: 2 };
    let value: i32 = int_box.second();
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_matches_methods_by_four_concrete_generic_receiver_arguments() {
    assert_gpu_type_check_ok(
        r#"
struct QuadBox<A, B, C, D> {
    a: A,
    b: B,
    c: C,
    d: D,
}

impl QuadBox<i32, bool, i32, bool> {
    fn pick(self) -> bool {
        return self.d;
    }
}

impl QuadBox<i32, bool, bool, i32> {
    fn pick(self) -> i32 {
        return self.d;
    }
}

fn main() {
    let left: QuadBox<i32, bool, i32, bool> = QuadBox { a: 1, b: true, c: 2, d: false };
    let right: QuadBox<i32, bool, bool, i32> = QuadBox { a: 1, b: true, c: false, d: 4 };
    let flag: bool = left.pick();
    let value: i32 = right.pick();
    if (flag) {
        return value;
    }
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_resolves_methods_on_generic_field_receivers_from_member_records() {
    assert_gpu_type_check_ok(
        r#"
struct Boxed<T> {
    value: T,
}

struct Holder {
    item: Boxed<i32>,
}

impl Boxed<i32> {
    fn read(self) -> i32 {
        return self.value;
    }
}

fn read_holder(holder: Holder) -> i32 {
    return holder.item.read();
}

fn main() {
    return 0;
}
"#,
    );
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
fn type_checker_accepts_direct_generic_function_at_two_concrete_types() {
    assert_gpu_type_check_ok(
        r#"
fn identity<T>(value: T) -> T {
    return value;
}

fn main() {
    let number: i32 = identity(7);
    let flag: bool = identity(false);
    if (flag) {
        return number;
    }
    return 0;
}
"#,
    );
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

trait Other<T> {
    fn other(value: T) -> bool;
}

impl Bound<i32> for i32 {
    fn check(value: i32) -> bool {
        return value > 0;
    }
}

impl Other<i32> for i32 {
    fn other(value: i32) -> bool {
        return value == 7;
    }
}

fn keep<T: Bound<T> + Other<T> >(value: T) -> T {
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
fn type_checker_reports_missing_trait_impl_obligation_diagnostic_on_gpu() {
    assert_gpu_type_check_diagnostic(
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
    let flag: bool = keep(true);
    if (flag) {
        return 1;
    }
    return 0;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "let flag: bool = keep(true);",
            "no matching impl satisfies this call",
        ],
    );
}

#[test]
fn type_checker_rejects_overlapping_trait_impls_without_waiting_for_a_call_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Marker<T> {
}

impl Marker<i32> for i32 {
}

impl Marker<i32> for i32 {
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Marker<i32> for i32 {",
            "trait impl overlaps an existing impl for the same trait and target",
            "make each supported trait impl key unique",
        ],
    );
}

#[test]
fn type_checker_reports_trait_method_generics_on_trait_declaration() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Factory {
    fn make<T>(value: T) -> T;
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
fn type_checker_rejects_trait_impl_method_signatures_beyond_gpu_param_width() {
    let trait_params = (0..33)
        .map(|i| format!("p{i}: T"))
        .collect::<Vec<_>>()
        .join(", ");
    let impl_params = (0..33)
        .map(|i| {
            if i == 32 {
                format!("p{i}: bool")
            } else {
                format!("p{i}: i32")
            }
        })
        .collect::<Vec<_>>()
        .join(", ");
    let src = format!(
        r#"
trait Wide<T> {{
    fn check({trait_params}) -> bool;
}}

impl Wide<i32> for i32 {{
    fn check({impl_params}) -> bool {{
        return true;
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
            "trait impl method has the wrong number of parameters",
            "match each implemented method's parameter list to the trait declaration",
        ],
    );
}

#[test]
fn type_checker_substitutes_trait_bound_arguments_per_generic_call_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait Rel<T> {
}

impl Rel<bool> for i32 {
}

impl Rel<i32> for bool {
}

fn keep<T, U>(left: T, right: U) -> T where T: Rel<U> {
    return left;
}

fn main() {
    let number: i32 = keep(7, true);
    let flag: bool = keep(false, 1);
    if (flag) {
        return number;
    }
    return 0;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
trait Rel<T> {
}

impl Rel<bool> for i32 {
}

fn keep<T, U>(left: T, right: U) -> T where T: Rel<U> {
    return left;
}

fn main() {
    let value: i32 = keep(7, 1);
    return value;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "let value: i32 = keep(7, 1);",
            "no matching impl satisfies this call",
        ],
    );
}

#[test]
fn type_checker_substitutes_trait_bound_subjects_from_nonzero_generic_slots_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait Supports<T> {
}

impl Supports<i32> for bool {
}

fn keep_right<T, U>(left: T, right: U) -> U where U: Supports<T> {
    return right;
}

fn main() {
    let flag: bool = keep_right(1, false);
    if (flag) {
        return 1;
    }
    return 0;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
trait Supports<T> {
}

impl Supports<bool> for bool {
}

fn keep_right<T, U>(left: T, right: U) -> U where U: Supports<T> {
    return right;
}

fn main() {
    let flag: bool = keep_right(1, false);
    if (flag) {
        return 1;
    }
    return 0;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "let flag: bool = keep_right(1, false);",
            "no matching impl satisfies this call",
        ],
    );
}

#[test]
fn type_checker_substitutes_two_trait_bound_arguments_from_generic_slots_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait Combines<Left, Right> {
}

impl Combines<i32, bool> for bool {
}

fn keep_middle<T, U, V>(left: T, middle: U, right: V) -> U where U: Combines<T, V> {
    return middle;
}

fn main() {
    let flag: bool = keep_middle(1, false, true);
    if (flag) {
        return 1;
    }
    return 0;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
trait Combines<Left, Right> {
}

impl Combines<i32, i32> for bool {
}

fn keep_middle<T, U, V>(left: T, middle: U, right: V) -> U where U: Combines<T, V> {
    return middle;
}

fn main() {
    let flag: bool = keep_middle(1, false, true);
    if (flag) {
        return 1;
    }
    return 0;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "let flag: bool = keep_middle(1, false, true);",
            "no matching impl satisfies this call",
        ],
    );
}

#[test]
fn type_checker_reports_trait_bounds_beyond_bounded_argument_width_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Rel3<First, Second, Third> {
}

fn keep<T>(value: T) -> T where T: Rel3<i32, bool, i32> {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "fn keep<T>(value: T) -> T where T: Rel3<i32, bool, i32> {",
            "trait bound exceeds the current GPU predicate argument limit",
        ],
    );
}

#[test]
fn type_checker_reports_trait_impls_beyond_bounded_argument_width_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Rel3<First, Second, Third> {
}

impl Rel3<i32, bool, i32> for i32 {
}

fn main() {
    return 0;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "impl Rel3<i32, bool, i32> for i32 {",
            "trait bound exceeds the current GPU predicate argument limit",
        ],
    );
}

#[test]
fn type_checker_reports_nested_trait_bound_argument_shapes_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

trait Rel<Value> {
}

fn keep<T>(value: T) -> T where T: Rel<Boxed<i32>> {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "fn keep<T>(value: T) -> T where T: Rel<Boxed<i32>> {",
            "trait bound argument shape is not supported by the current GPU predicate row",
        ],
    );
}

#[test]
fn type_checker_reports_unapplied_generic_trait_bound_arguments_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

trait Rel<Value> {
}

fn keep<T>(value: T) -> T where T: Rel<Boxed> {
    return value;
}

fn main() {
    return 0;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "fn keep<T>(value: T) -> T where T: Rel<Boxed> {",
            "trait bound argument shape is not supported by the current GPU predicate row",
        ],
    );

    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

trait Rel<Value> {
}

impl Rel<Boxed> for i32 {
}

fn main() {
    return 0;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "impl Rel<Boxed> for i32 {",
            "trait bound argument shape is not supported by the current GPU predicate row",
        ],
    );
}

#[test]
fn type_checker_reports_reference_trait_bound_argument_shapes_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Rel<Value> {
}

fn keep<T>(value: T) -> T where T: Rel<&i32> {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "fn keep<T>(value: T) -> T where T: Rel<&i32> {",
            "trait bound argument shape is not supported by the current GPU predicate row",
        ],
    );
}

#[test]
fn type_checker_reports_nested_trait_impl_argument_shapes_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

trait Rel<Value> {
}

impl Rel<Boxed<i32>> for i32 {
}

fn main() {
    return 0;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "impl Rel<Boxed<i32>> for i32 {",
            "trait bound argument shape is not supported by the current GPU predicate row",
        ],
    );
}

#[test]
fn type_checker_substitutes_mixed_concrete_and_generic_trait_bound_arguments_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait Rel<Fixed, Value> {
}

impl Rel<i32, bool> for i32 {
}

fn keep<T, U>(left: T, right: U) -> T where T: Rel<i32, U> {
    return left;
}

fn main() {
    let value: i32 = keep(7, false);
    return value;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
trait Rel<Fixed, Value> {
}

impl Rel<bool, bool> for i32 {
}

fn keep<T, U>(left: T, right: U) -> T where T: Rel<i32, U> {
    return left;
}

fn main() {
    let value: i32 = keep(7, false);
    return value;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "no matching impl satisfies this call",
        ],
    );
}

#[test]
fn type_checker_resolves_qualified_two_arg_trait_bounds_by_decl_identity() {
    assert_gpu_type_check_pack_ok(&[
        r#"
module core::rel;

pub trait Rel<Left, Right> {
    pub fn check(left: Left, right: Right) -> bool;
}

pub impl Rel<i32, bool> for i32 {
    pub fn check(left: i32, right: bool) -> bool {
        return right;
    }
}
"#,
        r#"
module app;

fn keep<T>(value: T) -> T where T: core::rel::Rel<i32, bool> {
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
module core::rel;

pub trait Rel<Left, Right> {
    pub fn check(left: Left, right: Right) -> bool;
}
"#,
            r#"
module other::rel;

pub trait Rel<Left, Right> {
    pub fn check(left: Left, right: Right) -> bool;
}

pub impl other::rel::Rel<i32, bool> for i32 {
    pub fn check(left: i32, right: bool) -> bool {
        return right;
    }
}
"#,
            r#"
module app;

fn keep<T>(value: T) -> T where T: core::rel::Rel<i32, bool> {
    return value;
}

fn main() {
    let value: i32 = keep(1);
    return value;
}
"#,
        ],
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "let value: i32 = keep(1);",
            "no matching impl satisfies this call",
        ],
    );
}

#[test]
fn type_checker_rejects_private_qualified_trait_bounds_across_modules() {
    assert_gpu_type_check_pack_ok(&[r#"
module core::secret;

trait Hidden<T> {
}

impl Hidden<i32> for i32 {
}

fn keep<T>(value: T) -> T where T: Hidden<T> {
    return value;
}

fn main() {
    let value: i32 = keep(1);
    return value;
}
"#]);

    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::secret;

trait Hidden<T> {
}

impl Hidden<i32> for i32 {
}
"#,
        r#"
module app;

fn keep<T>(value: T) -> T where T: core::secret::Hidden<T> {
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
fn type_checker_resolves_unqualified_imported_trait_predicates_by_module_visibility() {
    assert_gpu_type_check_pack_ok(&[
        r#"
module core::marker;

pub trait Marker<T> {
}
"#,
        r#"
module other::marker;

pub trait Marker<T> {
}

pub impl other::marker::Marker<bool> for bool {
}
"#,
        r#"
module app;

import core::marker;

pub impl Marker<i32> for i32 {
}

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
fn type_checker_checks_multi_payload_enum_constructor_ordinals_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
enum Pairish {
    Pair(i32, bool),
    Empty,
}

fn accept(value: Pairish) -> i32 {
    return 0;
}

fn main() {
    let value: Pairish = Pair(7, true);
    let empty: Pairish = Empty;
    return accept(value) + accept(empty);
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
enum Pairish {
    Pair(i32, bool),
    Empty,
}

fn main() {
    let value: Pairish = Pair(7, 8);
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_checks_multi_payload_enum_match_ordinals_on_gpu() {
    assert_gpu_type_check_pack_ok(&[r#"
module app::main;

enum Pairish {
    Pair(i32, bool),
    Empty,
}

fn choose(value: Pairish) -> i32 {
    return match (value) {
        Pair(left, right) -> left,
        Empty -> 0,
    };
}

fn main() {
    let value: Pairish = Pair(7, true);
    return choose(value);
}
"#]);
    assert_gpu_type_check_pack_rejects(&[r#"
module app::main;

enum Pairish {
    Pair(i32, bool),
    Empty,
}

fn choose(value: Pairish) -> i32 {
    return match (value) {
        Pair(left, right) -> right,
        Empty -> 0,
    };
}

fn main() {
    let value: Pairish = Pair(7, true);
    return choose(value);
}
"#]);
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
fn type_checker_substitutes_generic_enum_match_payloads_by_variant_slot_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
enum Either<LeftValue, RightValue> {
    Left(LeftValue),
    Right(RightValue),
}

fn unwrap_left<LeftValue, RightValue>(
    value: Either<LeftValue, RightValue>,
    fallback: LeftValue,
) -> LeftValue {
    return match (value) {
        Left(left) -> left,
        Right(right) -> fallback,
    };
}

fn unwrap_right<LeftValue, RightValue>(
    value: Either<LeftValue, RightValue>,
    fallback: RightValue,
) -> RightValue {
    return match (value) {
        Left(left) -> fallback,
        Right(right) -> right,
    };
}

fn main() {
    let left: Either<i32, bool> = Left(7);
    let right: Either<i32, bool> = Right(false);
    let number: i32 = unwrap_left(left, 0);
    let flag: bool = unwrap_right(right, true);
    if (flag) {
        return number;
    }
    return 0;
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
enum Either<LeftValue, RightValue> {
    Left(LeftValue),
    Right(RightValue),
}

fn wrong<LeftValue, RightValue>(
    value: Either<LeftValue, RightValue>,
    fallback: LeftValue,
) -> LeftValue {
    return match (value) {
        Left(left) -> left,
        Right(right) -> right,
    };
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

fn forwarded_copy(values: [i32; 4]) -> [i32; 4] {
    return copy(values);
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let copied: [i32; 4] = copy(values);
    let forwarded: [i32; 4] = forwarded_copy(copied);
    return forwarded[0];
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
fn type_checker_rejects_array_literal_local_element_mismatches_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
fn main() {
    let values: [bool; 2] = [true, 1];
    if (values[0]) {
        return 1;
    }
    return 0;
}
"#,
        "LNC0006",
        &[
            "type mismatch",
            "let values: [bool; 2] = [true, 1];",
            "expected a different type here",
        ],
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
fn take_pair(values: [i32; 2]) -> i32 {
    return values[0];
}

fn main() {
    let values: [i32; 4] = [1, 2, 3, 4];
    return take_pair(values);
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
    assert_gpu_type_check_rejects(
        r#"
fn choose(left: [i32; 4], right: [i32; 4]) -> [i32; 4] {
    return left;
}

fn copy_from_two_arguments(left: [i32; 4], right: [i32; 4]) -> [i32; 4] {
    return choose(left, right);
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
