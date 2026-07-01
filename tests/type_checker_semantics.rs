mod common;

use std::fmt::Write as _;

use laniusc_compiler::compiler::CompileError;

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

fn generated_wide_scalar_call_source(param_count: usize, bad_arg: Option<usize>) -> String {
    assert!(param_count > 0);
    let params = (0..param_count)
        .map(|i| format!("p{i}: i32"))
        .collect::<Vec<_>>()
        .join(",\n    ");
    let args = (0..param_count)
        .map(|i| {
            if bad_arg == Some(i) {
                "false".to_string()
            } else {
                i.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join(",\n        ");
    let return_param = format!("p{}", param_count - 1);

    format!(
        r#"
fn generated_wide(
    {params}
) -> i32 {{
    return {return_param};
}}

fn main() {{
    return generated_wide(
        {args}
    );
}}
"#
    )
}

fn generated_repeated_wide_scalar_call_source(
    param_count: usize,
    bad_arg: Option<usize>,
) -> String {
    assert!(param_count > 0);

    let mut source = String::with_capacity(param_count.saturating_mul(18));
    source.push_str("fn generated_wide(\n");
    for i in 0..param_count {
        let sep = if i + 1 == param_count { "\n" } else { ",\n" };
        writeln!(source, "    p{i}: i32{sep}").expect("write generated parameter");
    }
    writeln!(source, ") -> i32 {{").expect("write generated function signature");
    writeln!(source, "    return p{};", param_count - 1).expect("write generated return");
    source.push_str("}\n\nfn main() {\n    let value: i32 = 0;\n    return generated_wide(\n");
    for i in 0..param_count {
        let arg = if bad_arg == Some(i) { "false" } else { "value" };
        let sep = if i + 1 == param_count { "\n" } else { ",\n" };
        writeln!(source, "        {arg}{sep}").expect("write generated argument");
    }
    source.push_str("    );\n}\n");
    source
}

fn generated_wide_receiver_dispatch_source(arg_count: usize) -> String {
    assert!(arg_count > 4);

    let params = (0..arg_count)
        .map(|i| format!("T{i}"))
        .collect::<Vec<_>>()
        .join(", ");
    let shared_args = (0..arg_count - 1)
        .map(|_| "i32".to_string())
        .collect::<Vec<_>>()
        .join(", ");
    let bool_receiver = format!("{shared_args}, bool");
    let int_receiver = format!("{shared_args}, i32");
    let fields = (0..arg_count)
        .map(|i| format!("    value{i}: T{i},"))
        .collect::<Vec<_>>()
        .join("\n");
    let bool_values = (0..arg_count)
        .map(|i| {
            if i + 1 == arg_count {
                format!("value{i}: true")
            } else {
                format!("value{i}: {}", i + 1)
            }
        })
        .collect::<Vec<_>>()
        .join(", ");
    let int_values = (0..arg_count)
        .map(|i| format!("value{i}: {}", i + 1))
        .collect::<Vec<_>>()
        .join(", ");
    let tail_field = format!("value{}", arg_count - 1);

    format!(
        r#"
struct WideBox<{params}> {{
{fields}
}}

impl WideBox<{bool_receiver}> {{
    fn pick(self) -> bool {{
        return self.{tail_field};
    }}
}}

impl WideBox<{int_receiver}> {{
    fn pick(self) -> i32 {{
        return self.{tail_field};
    }}
}}

fn main() {{
    let left: WideBox<{bool_receiver}> = WideBox {{ {bool_values} }};
    let right: WideBox<{int_receiver}> = WideBox {{ {int_values} }};
    let flag: bool = left.pick();
    let value: i32 = right.pick();
    if (flag) {{
        return value;
    }}
    return 0;
}}
"#
    )
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
fn type_checker_reports_direct_call_arity_mismatch_reason() {
    assert_gpu_type_check_diagnostic(
        r#"
fn take_one(value: i32) -> i32 {
    return value;
}

fn main() {
    return take_one();
}
"#,
        "LNC0027",
        &[
            "error[LNC0027]: call resolution failed",
            "return take_one();",
            "call has the wrong number of arguments",
        ],
    );
}

#[test]
fn type_checker_rejects_direct_call_mismatch_within_cached_argument_width() {
    assert_gpu_type_check_diagnostic(
        r#"
fn take_pair(first: i32, second: i32) -> i32 {
    return first;
}

fn main() {
    return take_pair(1, false);
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "return take_pair(1, false);",
            "expected i32, found bool",
        ],
    );
}

#[test]
fn type_checker_accepts_direct_calls_beyond_cached_argument_width() {
    assert_gpu_type_check_ok(
        r#"
fn generated_sum(first: i32, second: i32, third: i32, fourth: i32, fifth: i32) -> i32 {
    return first + second + third + fourth + fifth;
}

fn main() {
    return generated_sum(1, 2, 3, 4, 5);
}
"#,
    );
}

#[test]
fn type_checker_rejects_direct_call_mismatch_beyond_cached_argument_width() {
    assert_gpu_type_check_diagnostic(
        r#"
fn generated_sum(first: i32, second: i32, third: i32, fourth: i32, fifth: i32) -> i32 {
    return first + second + third + fourth + fifth;
}

fn main() {
    return generated_sum(1, 2, 3, 4, true);
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "return generated_sum(1, 2, 3, 4, true);",
            "expected i32, found bool",
        ],
    );
}

#[test]
fn type_checker_reports_direct_call_mismatch_across_param_row_scan_boundary() {
    let src = generated_wide_scalar_call_source(257, Some(256));
    assert_gpu_type_check_diagnostic(
        &src,
        "LNC0006",
        &["error[LNC0006]: type mismatch", "expected i32, found bool"],
    );
}

#[test]
fn type_checker_accepts_direct_call_across_param_row_scan_boundary() {
    let src = generated_wide_scalar_call_source(257, None);
    assert_gpu_type_check_ok(&src);
}

#[test]
#[ignore = "large end-to-end capacity proof; run explicitly"]
fn type_checker_accepts_65k_direct_call_arguments() {
    let src = generated_repeated_wide_scalar_call_source(65_535, None);
    assert_gpu_type_check_ok(&src);
}

#[test]
#[ignore = "large end-to-end capacity proof; run explicitly"]
fn type_checker_reports_65k_direct_call_last_argument_mismatch() {
    let src = generated_repeated_wide_scalar_call_source(65_535, Some(65_534));
    assert_gpu_type_check_diagnostic(
        &src,
        "LNC0006",
        &["error[LNC0006]: type mismatch", "expected i32, found bool"],
    );
}

#[test]
fn type_checker_accepts_generic_array_calls_beyond_cached_argument_width() {
    assert_gpu_type_check_ok(
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
    );
}

#[test]
fn type_checker_rejects_repeated_array_const_generic_mismatch_beyond_cached_argument_width() {
    assert_gpu_type_check_rejects(
        r#"
fn same_len<T, const N: usize>(
    first: i32,
    second: i32,
    third: i32,
    fourth: i32,
    left: [T; N],
    right: [T; N]
) -> i32 {
    return first + second + third + fourth;
}

fn main() {
    let left: [i32; 2] = [1, 2];
    let right: [i32; 3] = [1, 2, 3];
    return same_len(1, 2, 3, 4, left, right);
}
"#,
    );
}

#[test]
fn type_checker_infers_array_generic_from_fifth_argument() {
    assert_gpu_type_check_ok(
        r#"
fn fifth_elem<T, const N: usize>(
    first: i32,
    second: i32,
    third: i32,
    fourth: i32,
    values: [T; N]
) -> T {
    return values[0];
}

fn main() {
    let values: [i32; 2] = [1, 2];
    let value: i32 = fifth_elem(1, 2, 3, 4, values);
    return value;
}
"#,
    );
}

#[test]
fn type_checker_infers_array_generic_from_fifth_generic_slot() {
    assert_gpu_type_check_ok(
        r#"
fn fifth_slot_elem<A, B, C, D, T, const N: usize>(
    a: A,
    b: B,
    c: C,
    d: D,
    values: [T; N]
) -> T {
    return values[0];
}

fn main() {
    let values: [i32; 2] = [1, 2];
    let value: i32 = fifth_slot_elem(true, 1, false, 2, values);
    return value;
}
"#,
    );
}

#[test]
fn type_checker_accepts_array_length_from_fifth_const_generic_slot() {
    assert_gpu_type_check_ok(
        r#"
fn same_len<T, const A: usize, const B: usize, const C: usize, const D: usize, const N: usize>(
    left: [T; N],
    right: [T; N]
) -> T {
    return left[0];
}

fn main() {
    let left: [i32; 2] = [1, 2];
    let right: [i32; 2] = [3, 4];
    let value: i32 = same_len(left, right);
    return value;
}
"#,
    );
}

#[test]
fn type_checker_rejects_array_length_mismatch_from_fifth_const_generic_slot() {
    assert_gpu_type_check_rejects(
        r#"
fn same_len<T, const A: usize, const B: usize, const C: usize, const D: usize, const N: usize>(
    left: [T; N],
    right: [T; N]
) -> T {
    return left[0];
}

fn main() {
    let left: [i32; 2] = [1, 2];
    let right: [i32; 3] = [3, 4, 5];
    let value: i32 = same_len(left, right);
    return value;
}
"#,
    );
}

#[test]
fn type_checker_accepts_contextual_array_return_from_fifth_argument() {
    assert_gpu_type_check_ok(
        r#"
fn copy_tail<T, const N: usize>(
    first: i32,
    second: i32,
    third: i32,
    fourth: i32,
    values: [T; N]
) -> [T; N] {
    return values;
}

fn main() {
    let values: [i32; 2] = [1, 2];
    let copied: [i32; 2] = copy_tail(1, 2, 3, 4, values);
    return copied[0];
}
"#,
    );
}

#[test]
fn type_checker_accepts_self_method_calls_beyond_cached_argument_width() {
    assert_gpu_type_check_ok(
        r#"
struct Counter {
    value: i32,
}

impl Counter {
    fn add(self, first: i32, second: i32, third: i32, fourth: i32, fifth: i32) -> i32 {
        return self.value + first + second + third + fourth + fifth;
    }
}

fn main() {
    let counter: Counter = Counter { value: 1 };
    return counter.add(1, 2, 3, 4, 5);
}
"#,
    );
}

#[test]
fn type_checker_rejects_self_method_mismatch_beyond_cached_argument_width() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Counter {
    value: i32,
}

impl Counter {
    fn add(self, first: i32, second: i32, third: i32, fourth: i32, fifth: i32) -> i32 {
        return self.value + first + second + third + fourth + fifth;
    }
}

fn main() {
    let counter: Counter = Counter { value: 1 };
    return counter.add(1, 2, 3, 4, true);
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "return counter.add(1, 2, 3, 4, true);",
            "expected i32, found bool",
        ],
    );
}

#[test]
fn type_checker_accepts_associated_function_calls_beyond_cached_argument_width() {
    assert_gpu_type_check_ok(
        r#"
struct Counter {
    value: i32,
}

impl Counter {
    fn sum(first: i32, second: i32, third: i32, fourth: i32, fifth: i32) -> i32 {
        return first + second + third + fourth + fifth;
    }
}

fn main() {
    return Counter::sum(1, 2, 3, 4, 5);
}
"#,
    );
}

#[test]
fn type_checker_rejects_associated_function_mismatch_beyond_cached_argument_width() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Counter {
    value: i32,
}

impl Counter {
    fn sum(first: i32, second: i32, third: i32, fourth: i32, fifth: i32) -> i32 {
        return first + second + third + fourth + fifth;
    }
}

fn main() {
    return Counter::sum(1, 2, 3, 4, true);
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "return Counter::sum(1, 2, 3, 4, true);",
            "expected i32, found bool",
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
fn type_checker_rejects_empty_return_from_explicit_generic_return_type_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
fn skip<T>(value: T) -> T {
    return;
}

fn main() {
    return 0;
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "return;",
            "expected generic parameter 0, found void",
        ],
    );
}

#[test]
fn type_checker_rejects_non_void_function_without_return_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
fn main() -> i32 {
    let value: i32 = 1;
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "fn main() -> i32 {",
            "expected i32, found void",
        ],
    );
}

#[test]
fn type_checker_accepts_top_level_fallthrough_return_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
fn choose(flag: bool) -> i32 {
    if (flag) {
        return 1;
    }
    return 2;
}

fn main() {
    return choose(false);
}
"#,
    );
}

#[test]
fn type_checker_accepts_direct_if_else_return_convergence_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
fn choose(flag: bool) -> i32 {
    if (flag) {
        return 1;
    } else {
        return 2;
    }
}

fn main() {
    return choose(true);
}
"#,
    );
}

#[test]
fn type_checker_rejects_branch_only_nested_return_convergence_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
fn choose(flag: bool, nested: bool) -> i32 {
    if (flag) {
        if (nested) {
            return 1;
        }
    } else {
        return 2;
    }
}

fn main() {
    return choose(true, false);
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "fn choose(flag: bool, nested: bool) -> i32 {",
            "expected i32, found void",
        ],
    );
}

#[test]
fn type_checker_accepts_nested_direct_if_else_return_convergence_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
fn choose(flag: bool, nested: bool) -> i32 {
    if (flag) {
        if (nested) {
            return 1;
        } else {
            return 2;
        }
    } else {
        return 3;
    }
}

fn main() {
    return choose(true, false);
}
"#,
    );
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
fn type_checker_rejects_deep_unary_string_operand_without_scan_window() {
    let src = format!(
        r#"
fn main() {{
    let flag: bool = {}"nope";
}}
"#,
        "!".repeat(17)
    );
    assert_gpu_type_check_rejects(&src);
}

#[test]
fn type_checker_rejects_deep_grouped_binary_left_operand_without_scan_window() {
    let left = format!("{}false{}", "(".repeat(33), ")".repeat(33));
    let src = format!(
        r#"
fn main() {{
    let value: i32 = {left} + 1;
}}
"#
    );
    assert_gpu_type_check_rejects(&src);
}

#[test]
fn type_checker_rejects_chained_binary_left_operand_type_mismatch() {
    assert_gpu_type_check_rejects(
        r#"
fn main() {
    let value: i32 = false + 1 + 2;
    return value;
}
"#,
    );
}

#[test]
fn type_checker_accepts_loop_control_inside_nested_hir_control_contexts() {
    assert_gpu_type_check_ok(
        r#"
fn main(limit: i32) -> i32 {
    let i: i32 = 0;
    while (i < limit) {
        i += 1;
        if (i == 2) {
            continue;
        }
        if (i == 4) {
            break;
        }
    }
    return i;
}
"#,
    );
}

#[test]
fn type_checker_rejects_loop_control_without_parser_owned_loop_context() {
    assert_gpu_type_check_diagnostic(
        r#"
fn main() -> i32 {
    break;
    return 0;
}
"#,
        "LNC0041",
        &[
            "error[LNC0041]: invalid loop control",
            "break;",
            "loop control statement is outside a loop",
        ],
    );
    assert_gpu_type_check_diagnostic(
        r#"
fn main() -> i32 {
    continue;
    return 0;
}
"#,
        "LNC0041",
        &[
            "error[LNC0041]: invalid loop control",
            "continue;",
            "loop control statement is outside a loop",
        ],
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
fn type_checker_rejects_duplicate_struct_field_declarations_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
struct Left {
    value: i32,
}

struct Right {
    value: bool,
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
struct Pair {
    value: i32,
    value: bool,
}

fn main() {
    return 0;
}
"#,
        "LNC0042",
        &[
            "error[LNC0042]: invalid member access",
            "value: bool,",
            "field name is already declared in this struct",
        ],
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
fn type_checker_accepts_member_field_in_binary_expression() {
    assert_gpu_type_check_ok(
        r#"
struct RenderSettings {
    width: i32,
    height: i32,
    samples_per_pixel: i32,
}

fn row_from_top(settings: RenderSettings, y: i32) -> i32 {
    let row: i32 = settings.height - 1 - y;
    return row;
}

fn main() {
    let settings: RenderSettings = RenderSettings {
        width: 16,
        height: 9,
        samples_per_pixel: 1,
    };
    return row_from_top(settings, 2);
}
"#,
    );
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
fn type_checker_resolves_associated_inherent_functions_on_type_paths() {
    assert_gpu_type_check_ok(
        r#"
struct Vec3 {
    x: i32,
    y: i32,
    z: i32,
}

impl Vec3 {
    fn new(x: i32, y: i32, z: i32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }
}

fn main() {
    let value: Vec3 = Vec3::new(1, 2, 3);
    return value.x + value.y + value.z;
}
"#,
    );
}

#[test]
fn type_checker_resolves_associated_call_result_method_receivers() {
    assert_gpu_type_check_ok(
        r#"
struct Vec3 {
    x: i32,
}

impl Vec3 {
    fn new(x: i32) -> Vec3 {
        return Vec3 { x: x };
    }

    fn add(self, right: Vec3) -> Vec3 {
        return Vec3 { x: self.x + right.x };
    }
}

fn main() {
    let value: Vec3 = Vec3::new(1).add(Vec3::new(2));
    return value.x;
}
"#,
    );
}

#[test]
fn type_checker_resolves_associated_call_result_method_receivers_with_bound_arg() {
    assert_gpu_type_check_ok(
        r#"
struct Vec3 {
    x: i32,
}

impl Vec3 {
    fn new(x: i32) -> Vec3 {
        return Vec3 { x: x };
    }

    fn add(self, right: Vec3) -> Vec3 {
        return Vec3 { x: self.x + right.x };
    }
}

fn main() {
    let right: Vec3 = Vec3::new(2);
    let value: Vec3 = Vec3::new(1).add(right);
    return value.x;
}
"#,
    );
}

#[test]
fn type_checker_resolves_generic_associated_inherent_functions_on_type_paths() {
    assert_gpu_type_check_ok(
        r#"
struct Boxed<T> {
    value: T,
}

impl<T> Boxed<T> {
    fn new(value: T) -> Boxed<T> {
        return Boxed { value: value };
    }
}

fn main() {
    let value: Boxed<i32> = Boxed<i32>::new(7);
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_resolves_associated_inherent_function_after_long_qualified_receiver_args() {
    assert_gpu_type_check_pack_ok(&[
        r#"
module a::b::c::d::e;

pub struct A { value: i32, }
pub struct B { value: i32, }
pub struct C { value: i32, }
pub struct D { value: i32, }
"#,
        r#"
module app;

import a::b::c::d::e;

struct Wide<A, B, C, D> {
    value: i32,
}

impl Wide<
    a::b::c::d::e::A,
    a::b::c::d::e::B,
    a::b::c::d::e::C,
    a::b::c::d::e::D
> {
    fn tag() -> i32 {
        return 7;
    }
}

fn main() {
    let value: i32 = Wide<
        a::b::c::d::e::A,
        a::b::c::d::e::B,
        a::b::c::d::e::C,
        a::b::c::d::e::D
    >::tag();
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_resolves_self_receiver_method_calls_inside_impl() {
    assert_gpu_type_check_ok(
        r#"
struct Vec3 {
    x: i32,
    y: i32,
}

impl Vec3 {
    fn dot(self, right: Vec3) -> i32 {
        return self.x * right.x + self.y * right.y;
    }

    fn magnitude_squared(self) -> i32 {
        return self.dot(self);
    }
}

fn main() {
    let value: Vec3 = Vec3 { x: 2, y: 3 };
    return value.magnitude_squared();
}
"#,
    );
}

#[test]
fn type_checker_validates_method_return_against_method_signature() {
    assert_gpu_type_check_ok(
        r#"
struct Scalar {
    value: f32,
}

impl Scalar {
    fn value(self) -> f32 {
        return self.value;
    }
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_resolves_qualified_call_with_nested_self_method_argument() {
    assert_gpu_type_check_pack_ok(&[
        r#"
module core::f32;

pub fn sqrt(value: f32) -> f32 {
    return value;
}
"#,
        r#"
module app::main;

import core::f32;

struct Vec3 {
    x: f32,
    y: f32,
}

impl Vec3 {
    fn dot(self, right: Vec3) -> f32 {
        return self.x * right.x + self.y * right.y;
    }

    fn length(self) -> f32 {
        return core::f32::sqrt(self.dot(self));
    }
}

fn main() {
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_resolves_f32_method_call_let_initializer() {
    assert_gpu_type_check_ok(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
}

impl Vec3 {
    fn dot(self, right: Vec3) -> f32 {
        return self.x * right.x + self.y * right.y;
    }

    fn length(self) -> f32 {
        return self.dot(self);
    }

    fn unit(self) -> Vec3 {
        let len: f32 = self.length();
        if (len == 0.0) {
            return self;
        }
        return Vec3 { x: self.x / len, y: self.y / len };
    }
}

fn main() {
    return 0;
}
"#,
    );
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

fn main() {
    let range: Range = Range { start: 1, end: 4 };
    if (range.contains(2)) {
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

fn main() {
    let range: Range = Range { start: 1, end: 4 };
    let wrong: bool = false;
    if (range.contains(wrong)) {
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
            assert!(rendered.contains("range.contains(wrong)"));
        }
        other => panic!("expected method argument type diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_checks_method_arguments_on_call_result_receivers() {
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

fn make_range() -> Range {
    return Range { start: 1, end: 4 };
}

fn main() {
    let wrong: bool = false;
    if (make_range().contains(wrong)) {
        return 1;
    }
    return 0;
}
"#,
    )
    .expect_err("call-result receiver method arguments should be type-checked");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0006");
            let rendered = diagnostic.render();
            assert!(rendered.contains("make_range().contains(wrong)"));
        }
        other => panic!("expected method argument type diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_struct_literal_returns_feed_call_result_method_receivers() {
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
}

#[test]
fn type_checker_resolves_chained_method_call_receivers() {
    assert_gpu_type_check_ok(
        r#"
struct Vec3 {
    x: i32,
}

impl Vec3 {
    fn add(self, right: Vec3) -> Vec3 {
        return Vec3 { x: self.x + right.x };
    }
}

fn main() {
    let left: Vec3 = Vec3 { x: 1 };
    let across: Vec3 = Vec3 { x: 2 };
    let up: Vec3 = Vec3 { x: 3 };
    let target: Vec3 = left.add(across).add(up);
    return target.x;
}
"#,
    );
}

#[test]
fn type_checker_resolves_field_receiver_chained_method_calls() {
    assert_gpu_type_check_ok(
        r#"
struct Vec3 {
    x: i32,
}

impl Vec3 {
    fn add(self, right: Vec3) -> Vec3 {
        return Vec3 { x: self.x + right.x };
    }
}

struct Camera {
    lower_left_corner: Vec3,
}

impl Camera {
    fn target(self, across: Vec3, up: Vec3) -> Vec3 {
        return self.lower_left_corner.add(across).add(up);
    }
}

fn main() {
    let origin: Vec3 = Vec3 { x: 1 };
    let camera: Camera = Camera { lower_left_corner: origin };
    let across: Vec3 = Vec3 { x: 2 };
    let up: Vec3 = Vec3 { x: 3 };
    let target: Vec3 = camera.target(across, up);
    return target.x;
}
"#,
    );
}

#[test]
fn type_checker_resolves_field_receiver_method_calls() {
    assert_gpu_type_check_ok(
        r#"
struct Vec3 {
    x: i32,
}

impl Vec3 {
    fn add(self, right: Vec3) -> Vec3 {
        return Vec3 { x: self.x + right.x };
    }
}

struct Camera {
    lower_left_corner: Vec3,
}

impl Camera {
    fn target(self, across: Vec3) -> Vec3 {
        return self.lower_left_corner.add(across);
    }
}

fn main() {
    let origin: Vec3 = Vec3 { x: 1 };
    let camera: Camera = Camera { lower_left_corner: origin };
    let across: Vec3 = Vec3 { x: 2 };
    let target: Vec3 = camera.target(across);
    return target.x;
}
"#,
    );
}

#[test]
fn type_checker_rejects_method_calls_beyond_gpu_argument_width() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Counter {
    value: i32,
}

impl Counter {
    fn sum(&self, first: i32, second: i32, third: i32, fourth: i32) -> i32 {
        return self.value + first + second + third + fourth;
    }
}

fn main() {
    let counter: Counter = Counter { value: 1 };
    return counter.sum(1, 2, 3, 4, 5);
}
"#,
        "LNC0027",
        &[
            "error[LNC0027]: call resolution failed",
            "call does not match a resolved function or method",
            "no supported function or method signature matches this receiver and argument list",
        ],
    );
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
fn type_checker_rejects_under_applied_inherent_impl_receiver_targets_on_gpu() {
    assert_gpu_type_check_diagnostic(
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
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl PairBox<i32> {",
            "trait impl target type is not supported here",
            "this compiler currently supports trait impls for scalar and non-generic nominal targets here",
        ],
    );
}

#[test]
fn type_checker_rejects_nested_inherent_impl_receiver_arguments_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

struct Holder<T> {
    value: T,
}

impl Holder<Boxed<i32>> {
    fn read(self) -> i32 {
        return self.value.value;
    }
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Holder<Boxed<i32>> {",
            "trait impl target type is not supported here",
            "this compiler currently supports trait impls for scalar and non-generic nominal targets here",
        ],
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
fn type_checker_substitutes_generic_inherent_method_returns_from_receiver() {
    assert_gpu_type_check_ok(
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
fn type_checker_rejects_inherent_method_level_generics_before_dispatch_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed {
    value: i32,
}

impl Boxed {
    fn choose<T>(self, value: T) -> T {
        return value;
    }
}

fn main() {
    let boxed: Boxed = Boxed { value: 1 };
    let value: bool = boxed.choose(true);
    if (value) {
        return boxed.value;
    }
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "fn choose<T>(self, value: T) -> T {",
            "trait method-level generics are not supported here",
        ],
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
fn type_checker_matches_methods_by_five_concrete_generic_receiver_arguments() {
    assert_gpu_type_check_ok(
        r#"
struct PentaBox<A, B, C, D, E> {
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
}

impl PentaBox<i32, bool, i32, bool, bool> {
    fn pick(self) -> bool {
        return self.e;
    }
}

impl PentaBox<i32, bool, i32, bool, i32> {
    fn pick(self) -> i32 {
        return self.e;
    }
}

fn main() {
    let left: PentaBox<i32, bool, i32, bool, bool> = PentaBox { a: 1, b: true, c: 2, d: false, e: true };
    let right: PentaBox<i32, bool, i32, bool, i32> = PentaBox { a: 1, b: true, c: 2, d: false, e: 4 };
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
fn type_checker_matches_methods_by_seventeen_concrete_generic_receiver_arguments() {
    let src = generated_wide_receiver_dispatch_source(17);
    assert_gpu_type_check_ok(&src);
}

#[test]
fn type_checker_substitutes_fifth_receiver_generic_arg_in_method_return() {
    assert_gpu_type_check_ok(
        r#"
struct WideBox<A, B, C, D, E> {
    value: E,
}

impl<A, B, C, D, E> WideBox<A, B, C, D, E> {
    fn read(self) -> E {
        return self.value;
    }
}

fn main() {
    let box: WideBox<bool, i32, bool, i32, i32> = WideBox { value: 7 };
    let value: i32 = box.read();
    return value;
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
fn type_checker_rejects_assigning_between_distinct_generic_struct_instances() {
    assert_gpu_type_check_rejects(
        r#"
struct Boxed<T> {
    value: T,
}

fn main() {
    let flag: Boxed<bool> = Boxed { value: true };
    let value: Boxed<i32> = flag;
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_rejects_nested_generic_struct_field_substitution_without_leaf_rows() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

struct Holder<T> {
    item: Boxed<T>,
}

fn main() {
    let flag: Boxed<bool> = Boxed { value: true };
    let holder: Holder<i32> = Holder { item: flag };
    return 0;
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "let holder: Holder<i32> = Holder { item: flag };",
            "value type does not match this context",
        ],
    );
}

#[test]
fn type_checker_substitutes_generic_struct_literal_fields_inside_generic_bodies() {
    assert_gpu_type_check_ok(
        r#"
struct Boxed<T> {
    value: T,
}

fn wrap<T>(value: T) -> Boxed<T> {
    return Boxed { value: value };
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
struct Boxed<T> {
    value: T,
}

fn wrap_wrong<T>(value: T) -> Boxed<T> {
    return Boxed { value: 1 };
}

fn main() {
    let boxed: Boxed<bool> = wrap_wrong(true);
    if (boxed.value) {
        return 1;
    }
    return 0;
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "return Boxed { value: 1 };",
            "value type is i32 but this context expects generic parameter 0",
        ],
    );
}

#[test]
fn type_checker_accepts_generic_type_instance_beyond_fixed_arg_record_width() {
    assert_gpu_type_check_ok(
        r#"
struct Five<A, B, C, D, E> {
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
}

fn main() {
    let item: Five<i32, bool, i32, bool, i32> = Five { a: 1, b: true, c: 2, d: false, e: 3 };
    return item.a;
}
"#,
    );
}

#[test]
fn type_checker_accepts_wide_generic_type_instance_local_assignment() {
    assert_gpu_type_check_ok(
        r#"
struct Five<A, B, C, D, E> {
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
}

fn main() {
    let item: Five<i32, bool, i32, bool, i32> = Five { a: 1, b: true, c: 2, d: false, e: 3 };
    let same: Five<i32, bool, i32, bool, i32> = item;
    return same.a;
}
"#,
    );
}

#[test]
fn type_checker_rejects_wide_generic_type_instance_local_assignment_mismatch() {
    assert_gpu_type_check_diagnostic(
        r#"
struct Five<A, B, C, D, E> {
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
}

fn main() {
    let item: Five<i32, bool, i32, bool, i32> = Five { a: 1, b: true, c: 2, d: false, e: 3 };
    let bad: Five<i32, bool, i32, bool, bool> = item;
    return 0;
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "let bad: Five<i32, bool, i32, bool, bool> = item;",
            "value type does not match this context",
        ],
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
fn type_checker_substitutes_trait_bound_subject_from_fifth_argument_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait Marker {
}

impl Marker for i32 {
}

fn keep_wide<T>(first: i32, second: i32, third: i32, fourth: i32, value: T) -> T where T: Marker {
    return value;
}

fn main() {
    let value: i32 = keep_wide(1, 2, 3, 4, 5);
    return value;
}
"#,
    );
}

#[test]
fn type_checker_rejects_missing_trait_bound_for_fifth_argument_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Marker {
}

impl Marker for bool {
}

fn keep_wide<T>(first: i32, second: i32, third: i32, fourth: i32, value: T) -> T where T: Marker {
    return value;
}

fn main() {
    let value: i32 = keep_wide(1, 2, 3, 4, 5);
    return value;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "let value: i32 = keep_wide(1, 2, 3, 4, 5);",
            "no matching impl satisfies this call",
        ],
    );
}

#[test]
fn type_checker_substitutes_trait_bound_subject_from_fifth_generic_slot_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait Marker {
}

impl Marker for i32 {
}

fn keep_fifth<A, B, C, D, T>(a: A, b: B, c: C, d: D, value: T) -> T where T: Marker {
    return value;
}

fn main() {
    let value: i32 = keep_fifth(true, 1, false, 2, 5);
    return value;
}
"#,
    );
}

#[test]
fn type_checker_rejects_missing_trait_bound_for_fifth_generic_slot_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Marker {
}

impl Marker for bool {
}

fn keep_fifth<A, B, C, D, T>(a: A, b: B, c: C, d: D, value: T) -> T where T: Marker {
    return value;
}

fn main() {
    let value: i32 = keep_fifth(true, 1, false, 2, 5);
    return value;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "let value: i32 = keep_fifth(true, 1, false, 2, 5);",
            "no matching impl satisfies this call",
        ],
    );
}

#[test]
fn type_checker_substitutes_trait_bound_subject_from_array_fifth_generic_slot_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
trait Marker {
}

impl Marker for i32 {
}

fn keep_array<A, B, C, D, T, const N: usize>(
    a: A,
    b: B,
    c: C,
    d: D,
    values: [T; N]
) -> T where T: Marker {
    return values[0];
}

fn main() {
    let values: [i32; 2] = [1, 2];
    let value: i32 = keep_array(true, 1, false, 2, values);
    return value;
}
"#,
    );
}

#[test]
fn type_checker_rejects_missing_trait_bound_for_array_fifth_generic_slot_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Marker {
}

impl Marker for bool {
}

fn keep_array<A, B, C, D, T, const N: usize>(
    a: A,
    b: B,
    c: C,
    d: D,
    values: [T; N]
) -> T where T: Marker {
    return values[0];
}

fn main() {
    let values: [i32; 2] = [1, 2];
    let value: i32 = keep_array(true, 1, false, 2, values);
    return value;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "let value: i32 = keep_array(true, 1, false, 2, values);",
            "no matching impl satisfies this call",
        ],
    );
}

#[test]
fn type_checker_rejects_missing_later_inline_trait_bound_on_gpu() {
    assert_gpu_type_check_diagnostic(
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

fn keep<T: Bound<T> + Other<T> >(value: T) -> T {
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
            "let value: i32 = keep(7);",
            "no matching impl satisfies this call",
        ],
    );
}

#[test]
fn type_checker_rejects_inline_trait_bound_chains_beyond_gpu_relation() {
    assert_gpu_type_check_diagnostic(
        r#"
trait First<T> {
}

trait Second<T> {
}

trait Third<T> {
}

impl First<i32> for i32 {
}

impl Second<i32> for i32 {
}

impl Third<i32> for i32 {
}

fn keep<T: First<T> + Second<T> + Third<T> >(value: T) -> T {
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
            "fn keep<T: First<T> + Second<T> + Third<T> >(value: T) -> T {",
            "trait bound relation is not supported here",
        ],
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
fn type_checker_rejects_symbolic_generic_trait_obligations_without_concrete_impl_key() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Eq<Value> {
}

impl Eq<i32> for i32 {
}

fn require_eq<T>(value: T) -> T where T: Eq<T> {
    return value;
}

fn forward<U>(value: U) -> U {
    return require_eq(value);
}

fn main() {
    return 0;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "return require_eq(value);",
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
fn type_checker_reports_trait_impl_visibility_mismatches_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
pub trait Marker<T> {
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
            "trait impl visibility does not match the resolved trait contract",
            "public trait impls and public traits must agree",
        ],
    );
}

#[test]
fn type_checker_reports_trait_impl_method_visibility_mismatches_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Marker<T> {
    pub fn check(value: T) -> bool;
}

impl Marker<i32> for i32 {
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
            "fn check(value: i32) -> bool {",
            "trait impl method visibility does not match the trait declaration",
            "match each impl method's visibility",
        ],
    );
}

#[test]
fn type_checker_rejects_public_trait_impl_methods_for_private_trait_contracts() {
    assert_gpu_type_check_ok(
        r#"
trait Marker<T> {
    fn check(value: T) -> bool;
}

impl Marker<i32> for i32 {
    fn check(value: i32) -> bool {
        return true;
    }
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
trait Marker<T> {
    fn check(value: T) -> bool;
}

impl Marker<i32> for i32 {
    pub fn check(value: i32) -> bool {
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
            "pub fn check(value: i32) -> bool {",
            "trait impl method visibility does not match the trait declaration",
            "match each impl method's visibility",
        ],
    );
}

#[test]
fn type_checker_rejects_duplicate_trait_impl_methods_with_stable_diagnostic() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Marker<T> {
    fn check(value: i32) -> bool;
}

impl Marker<i32> for i32 {
    fn check(value: i32) -> bool {
        return true;
    }

    fn check(value: i32) -> bool {
        return false;
    }
}

fn main() {
    return 0;
}
"#,
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "fn check(value: i32) -> bool {",
            "trait impl declares duplicate methods for the same trait contract",
            "give each implemented trait method a unique name",
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
        ],
    );
}

#[test]
fn type_checker_checks_trait_impl_method_signatures_beyond_old_param_width() {
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
            "trait impl method signature does not match the trait declaration",
            "match each implemented method's parameter and return types",
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
fn type_checker_rejects_calls_beyond_gpu_predicate_obligation_window() {
    let predicate_records = (0..33)
        .map(|i| {
            format!(
                r#"
trait Bound{i}<T> {{
}}

impl Bound{i}<i32> for i32 {{
}}
"#
            )
        })
        .collect::<String>();
    let bounds = (0..33)
        .map(|i| format!("Bound{i}<T>"))
        .collect::<Vec<_>>()
        .join(" + ");
    let src = format!(
        r#"
{predicate_records}
fn keep<T>(value: T) -> T where T: {bounds} {{
    return value;
}}

fn main() {{
    let value: i32 = keep(1);
    return value;
}}
"#
    );

    assert_gpu_type_check_diagnostic(
        &src,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "let value: i32 = keep(1);",
            "trait obligation exceeds the current trait-solver window",
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
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Rel3<i32, bool, i32> for i32 {",
            "trait impl header exceeds the current trait argument limit",
        ],
    );
}

#[test]
fn type_checker_points_two_arg_trait_impl_diagnostics_at_failing_argument() {
    assert_gpu_type_check_ok(
        r#"
trait Rel<Left, Right> {
}

impl Rel<i32, bool> for i32 {
}

fn main() {
    return 0;
}
"#,
    );

    let err = common::type_check_source_with_timeout(
        r#"
trait Rel<Left, Right> {
}

impl Rel<i32, Missing> for i32 {
}

fn main() {
    return 0;
}
"#,
    )
    .expect_err("unresolved second trait impl argument should fail trait validation");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0021");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("diagnostic should identify the failing trait impl argument");
            assert_eq!(
                label.source_line.as_deref(),
                Some("impl Rel<i32, Missing> for i32 {")
            );
            assert_eq!(label.column, 15);
            assert_eq!(label.length, "Missing".len());

            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0021]: invalid trait implementation"));
            assert!(rendered.contains("trait impl header contains an unknown trait argument type"));
        }
        other => panic!("expected second trait impl argument diagnostic, got {other:?}"),
    }
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
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Rel<Boxed> for i32 {",
            "trait impl header uses an unsupported trait argument shape",
        ],
    );
}

#[test]
fn type_checker_reports_reference_trait_bound_argument_shapes_on_gpu() {
    let err = common::type_check_source_with_timeout(
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
    )
    .expect_err("reference trait-bound arguments should fail trait validation");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0008");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("diagnostic should identify the unsupported trait argument");
            assert_eq!(
                label.source_line.as_deref(),
                Some("fn keep<T>(value: T) -> T where T: Rel<&i32> {")
            );
            assert!(
                (1..=label.source_line.as_ref().expect("source line").len())
                    .contains(&label.column),
                "diagnostic column should stay on the unsupported bound line, got {}",
                label.column
            );
            assert_eq!(label.length, 1);

            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0008]: unsatisfied trait bound"));
        }
        other => panic!("expected reference trait-bound argument diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_reports_second_trait_bound_argument_shape_diagnostics() {
    let err = common::type_check_source_with_timeout(
        r#"
trait Rel<First, Second> {
}

fn keep<T>(value: T) -> T where T: Rel<i32, &i32> {
    return value;
}

fn main() {
    return 0;
}
"#,
    )
    .expect_err("unsupported second trait-bound argument should fail trait validation");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0008");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("diagnostic should identify the unsupported trait argument");
            assert_eq!(
                label.source_line.as_deref(),
                Some("fn keep<T>(value: T) -> T where T: Rel<i32, &i32> {")
            );
            assert!(
                (1..=label.source_line.as_ref().expect("source line").len())
                    .contains(&label.column),
                "diagnostic column should stay on the unsupported bound line, got {}",
                label.column
            );
            assert_eq!(label.length, 1);

            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0008]: unsatisfied trait bound"));
        }
        other => panic!("expected second trait-bound argument diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_reports_reference_trait_impl_argument_shapes_on_gpu() {
    let err = common::type_check_source_with_timeout(
        r#"
trait Rel<Value> {
}

impl Rel<&i32> for i32 {
}

fn main() {
    return 0;
}
"#,
    )
    .expect_err("reference trait-impl arguments should fail trait validation");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0021");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("diagnostic should identify the unsupported trait impl argument");
            assert_eq!(
                label.source_line.as_deref(),
                Some("impl Rel<&i32> for i32 {")
            );
            assert_eq!(label.column, 10);
            assert_eq!(label.length, 1);

            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0021]: invalid trait implementation"));
            assert!(
                rendered.contains("trait impl header uses an unsupported trait argument shape")
            );
        }
        other => panic!("expected reference trait impl argument diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_reports_reference_trait_bound_heads_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
trait Marker {
}

fn keep<T>(value: T) -> T where T: &Marker {
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
            "fn keep<T>(value: T) -> T where T: &Marker {",
        ],
    );
}

#[test]
fn type_checker_points_generic_trait_impl_argument_diagnostics_at_argument_token() {
    let err = common::type_check_source_with_timeout(
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
    )
    .expect_err("generic trait impl arguments should fail GPU type checking");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0021");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("diagnostic should identify the unsupported trait argument");
            assert_eq!(
                label.source_line.as_deref(),
                Some("impl<T> Rel<T> for i32 {")
            );
            assert_eq!(label.column, 13);
            assert_eq!(label.length, 1);

            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0021]: invalid trait implementation"));
            assert!(rendered.contains(
                "trait impl header uses generic trait arguments that are not supported here"
            ));
            assert!(
                rendered
                    .contains("use concrete non-nested trait arguments in impl headers for now")
            );
        }
        other => panic!("expected generic trait impl argument diagnostic, got {other:?}"),
    }
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
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "impl Rel<Boxed<i32>> for i32 {",
            "trait impl header uses an unsupported trait argument shape",
        ],
    );
}

#[test]
fn type_checker_reports_imported_nested_trait_impl_argument_shapes_on_gpu() {
    assert_gpu_type_check_pack_diagnostic(
        &[
            r#"
module core::types;

pub struct Boxed<T> {
    value: T,
}

pub trait Rel<Value> {
}
"#,
            r#"
module app;

import core::types;

pub impl Rel<Boxed<i32>> for i32 {
}

fn main() {
    return 0;
}
"#,
        ],
        "LNC0021",
        &[
            "error[LNC0021]: invalid trait implementation",
            "pub impl Rel<Boxed<i32>> for i32 {",
            "trait impl header uses an unsupported trait argument shape",
        ],
    );
}

#[test]
fn type_checker_normalizes_alias_predicate_type_argument_leaves_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
type Count = i32;

trait Rel<Value> {
}

impl Rel<i32> for i32 {
}

fn keep<T>(value: T) -> T where T: Rel<Count> {
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
type Count = i32;

trait Rel<Value> {
}

impl Rel<Count> for i32 {
}

fn keep<T>(value: T) -> T where T: Rel<i32> {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
type Flag = bool;

trait Rel<Value> {
}

impl Rel<i32> for i32 {
}

fn keep<T>(value: T) -> T where T: Rel<Flag> {
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
            "let value: i32 = keep(7);",
            "no matching impl satisfies this call",
        ],
    );
}

#[test]
fn type_checker_normalizes_nominal_alias_predicate_type_argument_leaves_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
struct Key {
    value: i32,
}

type KeyAlias = Key;

trait Rel<Value> {
}

impl Rel<Key> for i32 {
}

fn keep<T>(value: T) -> T where T: Rel<KeyAlias> {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
struct Key {
    value: i32,
}

struct OtherKey {
    value: i32,
}

type KeyAlias = OtherKey;

trait Rel<Value> {
}

impl Rel<Key> for i32 {
}

fn keep<T>(value: T) -> T where T: Rel<KeyAlias> {
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
            "let value: i32 = keep(7);",
            "no matching impl satisfies this call",
        ],
    );
}

#[test]
fn type_checker_normalizes_qualified_alias_predicate_type_arguments_on_gpu() {
    assert_gpu_type_check_pack_ok(&[
        r#"
module core::types;

pub type Count = i32;

pub trait Rel<Value> {
}

pub impl Rel<i32> for i32 {
}
"#,
        r#"
module app;

fn keep<T, Count>(value: T, shadow: Count) -> T where T: core::types::Rel<core::types::Count> {
    let copied: Count = shadow;
    return value;
}

fn main() {
    let marker: bool = false;
    let value: i32 = keep(7, marker);
    return value;
}
"#,
    ]);

    assert_gpu_type_check_pack_diagnostic(
        &[
            r#"
module core::types;

pub type Flag = bool;

pub trait Rel<Value> {
}

pub impl Rel<i32> for i32 {
}
"#,
            r#"
module app;

fn keep<T>(value: T) -> T where T: core::types::Rel<core::types::Flag> {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#,
        ],
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "let value: i32 = keep(7);",
            "no matching impl satisfies this call",
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
fn type_checker_substitutes_alias_normalized_call_arguments_into_trait_bounds_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
type Count = i32;

trait Eq<Value> {
}

impl Eq<i32> for i32 {
}

fn require_eq<T>(value: T) -> T where T: Eq<T> {
    return value;
}

fn main() {
    let count: Count = 7;
    let value: Count = require_eq(count);
    return value;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
type Flag = bool;

trait Eq<Value> {
}

impl Eq<i32> for i32 {
}

fn require_eq<T>(value: T) -> T where T: Eq<T> {
    return value;
}

fn main() {
    let flag: Flag = false;
    let value: Flag = require_eq(flag);
    if (value) {
        return 1;
    }
    return 0;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "let value: Flag = require_eq(flag);",
            "no matching impl satisfies this call",
        ],
    );
}

#[test]
fn type_checker_substitutes_alias_normalized_bound_arguments_from_nonzero_slots_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
type Count = i32;

trait Rel<Value> {
}

impl Rel<i32> for bool {
}

fn keep_right<T, U>(left: T, right: U) -> U where U: Rel<T> {
    return right;
}

fn main() {
    let count: Count = 7;
    let value: bool = keep_right(count, false);
    if (value) {
        return 1;
    }
    return 0;
}
"#,
    );

    assert_gpu_type_check_diagnostic(
        r#"
type Flag = bool;

trait Rel<Value> {
}

impl Rel<i32> for bool {
}

fn keep_right<T, U>(left: T, right: U) -> U where U: Rel<T> {
    return right;
}

fn main() {
    let flag: Flag = false;
    let value: bool = keep_right(flag, true);
    if (value) {
        return 1;
    }
    return 0;
}
"#,
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "let value: bool = keep_right(flag, true);",
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
fn type_checker_rejects_private_bound_type_arguments_across_modules() {
    assert_gpu_type_check_pack_ok(&[r#"
module core::secret;

pub trait Rel<T> {
}

struct Secret {
    value: i32,
}

pub impl Rel<Secret> for i32 {
}

fn keep<T>(value: T) -> T where T: Rel<Secret> {
    return value;
}

fn main() {
    let value: i32 = keep(1);
    return value;
}
"#]);

    assert_gpu_type_check_pack_diagnostic(
        &[
            r#"
module core::secret;

pub trait Rel<T> {
}

struct Secret {
    value: i32,
}

pub impl Rel<Secret> for i32 {
}
"#,
            r#"
module app;

fn keep<T>(value: T) -> T where T: core::secret::Rel<core::secret::Secret> {
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
            "fn keep<T>(value: T) -> T where T: core::secret::Rel<core::secret::Secret> {",
        ],
    );
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
    assert_gpu_type_check_diagnostic(
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
        "LNC0008",
        &[
            "error[LNC0008]: unsatisfied trait bound",
            "fn keep<T: Bound<T> >(value: T) -> T {",
            "trait bound target does not resolve to a trait",
            "name a trait in the bound before relying on trait solving",
        ],
    );
}

#[test]
fn type_checker_rejects_unknown_bound_type_arguments_on_gpu() {
    assert_gpu_type_check_diagnostic(
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
        "LNC0007",
        &[
            "error[LNC0007]: unknown type",
            "fn keep<T>(value: T) -> T where T: Rel<T, Missing> {",
            "type not found",
        ],
    );
}

#[test]
fn type_checker_rejects_trait_bounds_on_const_generic_subjects_on_gpu() {
    let src = r#"
trait Marker {
}

fn keep<const N: usize>(value: i32) -> i32 where N: Marker {
    return value;
}

fn main() {
    return 0;
}
"#;

    let err = common::type_check_source_with_timeout(src)
        .expect_err("const generic trait-bound subjects should fail GPU type checking");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0008");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("diagnostic should identify the const generic subject");
            assert_eq!(
                label.source_line.as_deref(),
                Some("fn keep<const N: usize>(value: i32) -> i32 where N: Marker {")
            );
            assert_eq!(label.column, 50);
            assert_eq!(label.length, 1);

            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0008]: unsatisfied trait bound"));
            assert!(rendered.contains("trait bound subject must be a type generic parameter"));
            assert!(rendered.contains("use a declared type parameter as the bound subject"));
            assert!(rendered.contains("const generic parameters"));
        }
        other => panic!("expected const generic trait-bound diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_rejects_trait_bounds_on_non_callable_generic_declarations_on_gpu() {
    let err = common::type_check_source_with_timeout(
        r#"
trait Marker {
}

struct Boxed<T: Marker> {
    value: T,
}

fn main() {
    return 0;
}
"#,
    )
    .expect_err("declaration-level trait bounds should fail until instantiation obligations exist");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0008");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("diagnostic should identify the unsupported bound");
            assert_eq!(
                label.source_line.as_deref(),
                Some("struct Boxed<T: Marker> {")
            );
            assert_eq!(label.column, 17);
            assert_eq!(label.length, 6);
            assert_eq!(
                label.message,
                "trait bounds on this generic declaration are not enforced by the current trait solver"
            );
        }
        other => panic!("expected declaration-level trait-bound diagnostic, got {other:?}"),
    }
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
fn type_checker_rejects_enum_match_pattern_payload_arity_mismatch_on_gpu() {
    assert_gpu_type_check_diagnostic(
        r#"
enum Pairish {
    Pair(i32, bool),
    Empty,
}

fn choose(value: Pairish) -> i32 {
    return match (value) {
        Pair(left) -> left,
        Empty -> 0,
    };
}

fn main() {
    let value: Pairish = Pair(7, true);
    return choose(value);
}
"#,
        "LNC0006",
        &[
            "error[LNC0006]: type mismatch",
            "Pair(left) -> left",
            "value type does not match this context",
        ],
    );
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

    assert_gpu_type_check_diagnostic(
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
        "LNC0006",
        &["error[LNC0006]: type mismatch", "Right(right) -> right,"],
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
fn type_checker_accepts_struct_array_literal_elements_on_gpu() {
    assert_gpu_type_check_ok(
        r#"
struct Pair {
    left: i32,
    right: i32,
}

fn values() -> [Pair; 2] {
    return [
        Pair { left: 1, right: 2 },
        Pair { left: 3, right: 4 },
    ];
}

fn main() {
    let local: [Pair; 2] = [
        Pair { left: 5, right: 6 },
        Pair { left: 7, right: 8 },
    ];
    let returned: [Pair; 2] = values();
    return local[0].left + returned[1].right;
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
    assert_gpu_type_check_diagnostic(
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
        "LNC0043",
        &[
            "error[LNC0043]: invalid array return",
            "return choose(left, right);",
            "array return value is not valid in this context",
        ],
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
    assert_gpu_type_check_diagnostic(
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
        "LNC0042",
        &[
            "error[LNC0042]: invalid member access",
            "return self.right;",
            "this value does not have the requested field",
        ],
    );
    assert_gpu_type_check_diagnostic(
        r#"
fn main() {
    let value: i32 = 1;
    return value.field;
}
"#,
        "LNC0042",
        &[
            "error[LNC0042]: invalid member access",
            "return value.field;",
            "this value does not have the requested field",
        ],
    );
}

#[path = "type_checker_semantics/trait_methods_control.rs"]
mod trait_methods_control;
