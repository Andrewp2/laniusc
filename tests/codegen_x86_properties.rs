mod common;

use laniusc::compiler::{
    CompileError,
    compile_source_pack_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen,
};

struct GeneratedX86Names {
    module_path: Option<&'static str>,
    combine: &'static str,
    left: &'static str,
    right: &'static str,
    total: &'static str,
    value: &'static str,
}

struct GeneratedX86Case {
    name: &'static str,
    source: String,
    expected_exit: i32,
}

struct GeneratedX86RejectionCase {
    name: &'static str,
    source: String,
}

struct GeneratedX86SourcePackCase {
    name: &'static str,
    sources: Vec<String>,
    expected_exit: i32,
}

struct GeneratedX86ArrayFoldNames {
    module_path: &'static str,
    fold: &'static str,
    values: &'static str,
    bias: &'static str,
    index: &'static str,
    term: &'static str,
    total: &'static str,
    numbers: &'static str,
}

struct GeneratedX86CallArgExprNames {
    module_path: &'static str,
    callee: &'static str,
    first: &'static str,
    second: &'static str,
    third: &'static str,
    fourth: &'static str,
    local_a: &'static str,
    local_b: &'static str,
}

fn assert_x86_64_elf_header(bytes: &[u8]) {
    assert!(bytes.len() >= 20, "ELF output too small: {}", bytes.len());
    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[4], 2, "ELF64 class");
    assert_eq!(bytes[5], 1, "little-endian ELF");
    assert_eq!(u16::from_le_bytes(bytes[18..20].try_into().unwrap()), 62);
}

fn compile_source(context: &str, source: &str) -> Vec<u8> {
    let source = source.to_owned();
    common::run_gpu_codegen_with_timeout(context, move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .unwrap_or_else(|err| panic!("{context} should compile to x86_64: {err}"))
}

fn compile_source_pack(context: &str, sources: Vec<String>) -> Vec<u8> {
    common::run_gpu_codegen_with_timeout(context, move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .unwrap_or_else(|err| panic!("{context} source pack should compile to x86_64: {err}"))
}

fn expect_lnc0017_x86_diagnostic(context: &str, source: String) {
    let err = common::run_gpu_codegen_with_timeout(context, move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("generated x86 rejection case should fail closed");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "x86 rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic.message.contains("unsupported x86 call ABI")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the native call ABI boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert!(
                label.line > 0 && label.column > 0,
                "diagnostic should include a concrete source span: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

fn generated_x86_program(names: GeneratedX86Names, callee_uses_local: bool) -> String {
    let combine_body = if callee_uses_local {
        format!(
            "    let {total}: i32 = {left} + {right};\n    return {total};",
            total = names.total,
            left = names.left,
            right = names.right,
        )
    } else {
        format!(
            "    return {left} + {right};",
            left = names.left,
            right = names.right,
        )
    };

    format!(
        r#"
fn {combine}({left}: i32, {right}: i32) -> i32 {{
{combine_body}
}}

fn main() {{
    let {value}: i32 = {combine}(5, 7);
    return {value};
}}
"#,
        combine = names.combine,
        left = names.left,
        right = names.right,
        value = names.value,
        combine_body = combine_body,
    )
}

fn generated_x86_source_pack(names: GeneratedX86Names, callee_uses_local: bool) -> Vec<String> {
    let module_path = names
        .module_path
        .expect("source-pack cases should provide a module path");
    let combine_body = if callee_uses_local {
        format!(
            "    let {total}: i32 = {left} + {right};\n    return {total};",
            total = names.total,
            left = names.left,
            right = names.right,
        )
    } else {
        format!(
            "    return {left} + {right};",
            left = names.left,
            right = names.right,
        )
    };

    vec![
        format!(
            r#"
module {module_path};
pub fn {combine}({left}: i32, {right}: i32) -> i32 {{
{combine_body}
}}
"#,
            module_path = module_path,
            combine = names.combine,
            left = names.left,
            right = names.right,
            combine_body = combine_body,
        ),
        format!(
            r#"
module app::main;
import {module_path};
fn main() {{
    let {value}: i32 = {module_path}::{combine}(5, 7);
    return {value};
}}
"#,
            module_path = module_path,
            combine = names.combine,
            value = names.value,
        ),
    ]
}

fn generated_x86_cases() -> [GeneratedX86Case; 3] {
    [
        GeneratedX86Case {
            name: "helper_like_names_do_not_control_codegen",
            source: generated_x86_program(
                GeneratedX86Names {
                    module_path: None,
                    combine: "wrapping_mul",
                    left: "value",
                    right: "rhs",
                    total: "sum",
                    value: "computed",
                },
                false,
            ),
            expected_exit: 12,
        },
        GeneratedX86Case {
            name: "helper_like_let_bound_callee_keeps_semantics",
            source: generated_x86_program(
                GeneratedX86Names {
                    module_path: None,
                    combine: "wrapping_mul",
                    left: "value",
                    right: "rhs",
                    total: "sum",
                    value: "computed",
                },
                true,
            ),
            expected_exit: 12,
        },
        GeneratedX86Case {
            name: "renamed_let_bound_callee_keeps_semantics",
            source: generated_x86_program(
                GeneratedX86Names {
                    module_path: None,
                    combine: "combine_values",
                    left: "first",
                    right: "second",
                    total: "joined",
                    value: "observed",
                },
                true,
            ),
            expected_exit: 12,
        },
    ]
}

fn generated_x86_source_pack_cases() -> Vec<GeneratedX86SourcePackCase> {
    vec![
        GeneratedX86SourcePackCase {
            name: "source_pack_helper_like_names_do_not_control_codegen",
            sources: generated_x86_source_pack(
                GeneratedX86Names {
                    module_path: Some("core::i32"),
                    combine: "wrapping_mul",
                    left: "value",
                    right: "rhs",
                    total: "sum",
                    value: "computed",
                },
                false,
            ),
            expected_exit: 12,
        },
        GeneratedX86SourcePackCase {
            name: "source_pack_renamed_let_bound_callee_keeps_semantics",
            sources: generated_x86_source_pack(
                GeneratedX86Names {
                    module_path: Some("helpers::math"),
                    combine: "combine_values",
                    left: "first",
                    right: "second",
                    total: "joined",
                    value: "observed",
                },
                true,
            ),
            expected_exit: 12,
        },
    ]
}

fn weighted_sum_expected(values: [i32; 4], bias: i32) -> i32 {
    let mut total = 0;
    for (index, value) in values.into_iter().enumerate() {
        let term = value * (index as i32 + 1);
        if term + bias > 10 {
            total += term - bias;
        } else {
            total += term + bias;
        }
    }
    total
}

fn generated_x86_array_fold_source_pack(
    name: &'static str,
    names: GeneratedX86ArrayFoldNames,
    values: [i32; 4],
    bias: i32,
) -> GeneratedX86SourcePackCase {
    let values_literal = values
        .into_iter()
        .map(|value| value.to_string())
        .collect::<Vec<_>>()
        .join(", ");
    let sources = vec![
        format!(
            r#"
module {module_path};
pub fn {fold}({values}: [i32; 4], {bias}: i32) -> i32 {{
    let {index}: i32 = 0;
    let {total}: i32 = 0;
    while ({index} < 4) {{
        let {term}: i32 = {values}[{index}] * ({index} + 1);
        if (({term} + {bias}) > 10) {{
            {total} += {term} - {bias};
        }} else {{
            {total} += {term} + {bias};
        }}
        {index} += 1;
    }}
    return {total};
}}
"#,
            module_path = names.module_path,
            fold = names.fold,
            values = names.values,
            bias = names.bias,
            index = names.index,
            term = names.term,
            total = names.total,
        ),
        format!(
            r#"
module app::main;
import {module_path};
fn main() {{
    let {numbers}: [i32; 4] = [{values_literal}];
    return {module_path}::{fold}({numbers}, {bias_value});
}}
"#,
            module_path = names.module_path,
            fold = names.fold,
            numbers = names.numbers,
            values_literal = values_literal,
            bias_value = bias,
        ),
    ];

    GeneratedX86SourcePackCase {
        name,
        sources,
        expected_exit: weighted_sum_expected(values, bias),
    }
}

fn generated_x86_nested_source_pack_flow_cases() -> Vec<GeneratedX86SourcePackCase> {
    vec![
        generated_x86_array_fold_source_pack(
            "source_pack_helper_like_array_loop_branch_call",
            GeneratedX86ArrayFoldNames {
                module_path: "core::i32",
                fold: "wrapping_mul",
                values: "value",
                bias: "rhs",
                index: "index",
                term: "term",
                total: "sum",
                numbers: "input",
            },
            [2, 3, 4, 5],
            2,
        ),
        generated_x86_array_fold_source_pack(
            "source_pack_renamed_array_loop_branch_call",
            GeneratedX86ArrayFoldNames {
                module_path: "helpers::fold",
                fold: "weighted_sum",
                values: "items",
                bias: "offset",
                index: "cursor",
                term: "weighted",
                total: "acc",
                numbers: "numbers",
            },
            [1, 4, 2, 6],
            3,
        ),
    ]
}

fn generated_x86_call_arg_expr_source_pack(
    name: &'static str,
    names: GeneratedX86CallArgExprNames,
    local_a_value: i32,
    local_b_value: i32,
) -> GeneratedX86SourcePackCase {
    let expected_first = local_a_value - local_b_value;
    let expected_second = local_b_value - 2;
    let expected_third = local_a_value - 3;
    let expected_fourth = local_b_value - 1;
    let expected_exit =
        expected_first * 10 + expected_second * 3 + expected_third - expected_fourth;
    let sources = vec![
        format!(
            r#"
module {module_path};
pub fn {callee}({first}: i32, {second}: i32, {third}: i32, {fourth}: i32) -> i32 {{
    return {first} * 10 + {second} * 3 + {third} - {fourth};
}}
"#,
            module_path = names.module_path,
            callee = names.callee,
            first = names.first,
            second = names.second,
            third = names.third,
            fourth = names.fourth,
        ),
        format!(
            r#"
module app::main;
import {module_path};
fn main() {{
    let {local_a}: i32 = {local_a_value};
    let {local_b}: i32 = {local_b_value};
    return {module_path}::{callee}({local_a} - {local_b}, {local_b} - 2, {local_a} - 3, {local_b} - 1);
}}
"#,
            module_path = names.module_path,
            callee = names.callee,
            local_a = names.local_a,
            local_b = names.local_b,
            local_a_value = local_a_value,
            local_b_value = local_b_value,
        ),
    ];

    GeneratedX86SourcePackCase {
        name,
        sources,
        expected_exit,
    }
}

fn generated_x86_call_arg_expr_cases() -> Vec<GeneratedX86SourcePackCase> {
    vec![
        generated_x86_call_arg_expr_source_pack(
            "source_pack_helper_like_local_expr_call_args",
            GeneratedX86CallArgExprNames {
                module_path: "core::i32",
                callee: "wrapping_mul",
                first: "value",
                second: "rhs",
                third: "shift",
                fourth: "mask",
                local_a: "computed",
                local_b: "bias",
            },
            9,
            5,
        ),
        generated_x86_call_arg_expr_source_pack(
            "source_pack_renamed_local_expr_call_args",
            GeneratedX86CallArgExprNames {
                module_path: "helpers::math",
                callee: "combine_values",
                first: "left",
                second: "right",
                third: "scale",
                fourth: "offset",
                local_a: "observed",
                local_b: "delta",
            },
            9,
            5,
        ),
    ]
}

fn generated_x86_overwide_call(
    callee: &'static str,
    first_param: &'static str,
) -> GeneratedX86RejectionCase {
    let source = format!(
        r#"
fn {callee}({first_param}: i32, b: i32, c: i32, d: i32, e: i32) -> i32 {{
    return {first_param} + b + c + d + e;
}}

fn main() {{
    return {callee}(1, 2, 3, 4, 5);
}}
"#
    );

    GeneratedX86RejectionCase {
        name: callee,
        source,
    }
}

fn generated_x86_rejection_cases() -> [GeneratedX86RejectionCase; 2] {
    [
        generated_x86_overwide_call("wrapping_mul", "value"),
        generated_x86_overwide_call("combine_values", "first"),
    ]
}

fn generated_x86_loop_contained_call(callee: &'static str) -> GeneratedX86RejectionCase {
    let source = format!(
        r#"
fn {callee}(value: i32) -> i32 {{
    return value + 1;
}}

fn main() {{
    let value: i32 = 0;
    while (value < 2) {{
        value = {callee}(value);
    }}
    return value;
}}
"#
    );

    GeneratedX86RejectionCase {
        name: callee,
        source,
    }
}

fn generated_x86_loop_contained_call_cases() -> [GeneratedX86RejectionCase; 2] {
    [
        generated_x86_loop_contained_call("wrapping_mul"),
        generated_x86_loop_contained_call("advance_value"),
    ]
}

fn generated_x86_loop_let_initializer_call(
    callee: &'static str,
    binding: &'static str,
) -> GeneratedX86RejectionCase {
    let source = format!(
        r#"
fn {callee}(value: i32) -> i32 {{
    return value + 1;
}}

fn main() {{
    let value: i32 = 0;
    while (value < 2) {{
        let {binding}: i32 = {callee}(value);
        value = {binding};
    }}
    return value;
}}
"#
    );

    GeneratedX86RejectionCase {
        name: callee,
        source,
    }
}

fn generated_x86_loop_let_initializer_call_cases() -> [GeneratedX86RejectionCase; 2] {
    [
        generated_x86_loop_let_initializer_call("advance_value", "next_value"),
        generated_x86_loop_let_initializer_call("compute_next", "observed"),
    ]
}

fn generated_x86_postfix_rejection_cases() -> [GeneratedX86RejectionCase; 2] {
    [
        GeneratedX86RejectionCase {
            name: "postfix_increment_helper_like_binding",
            source: r#"
fn main() {
    let wrapping_mul: i32 = 0;
    wrapping_mul++;
    return wrapping_mul;
}
"#
            .to_owned(),
        },
        GeneratedX86RejectionCase {
            name: "postfix_decrement_renamed_binding",
            source: r#"
fn main() {
    let observed: i32 = 2;
    observed--;
    return observed;
}
"#
            .to_owned(),
        },
    ]
}

fn generated_x86_regalloc_chunk_boundary_source(
    binding_prefix: &'static str,
    binding_count: usize,
) -> String {
    let mut source = format!("fn main() {{\n    let {binding_prefix}0: i32 = 0;\n");
    for binding_i in 1..binding_count {
        source.push_str(&format!(
            "    let {binding_prefix}{binding_i}: i32 = {binding_prefix}{} + 1;\n",
            binding_i - 1
        ));
    }
    source.push_str(&format!(
        "    return {binding_prefix}{};\n}}\n",
        binding_count - 1
    ));
    source
}

fn generated_x86_regalloc_chunk_boundary_cases() -> [GeneratedX86RejectionCase; 2] {
    [
        GeneratedX86RejectionCase {
            name: "regalloc_chunk_helper_like_value_defs",
            source: generated_x86_regalloc_chunk_boundary_source("wrapping_mul", 40),
        },
        GeneratedX86RejectionCase {
            name: "regalloc_chunk_renamed_value_defs",
            source: generated_x86_regalloc_chunk_boundary_source("observed", 40),
        },
    ]
}

#[test]
fn generated_x86_programs_are_name_and_shape_independent() {
    for case in generated_x86_cases() {
        let bytes = compile_source(case.name, &case.source);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should exit with the generated program value",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_source_pack_calls_are_name_and_shape_independent() {
    for case in generated_x86_source_pack_cases() {
        let bytes = compile_source_pack(case.name, case.sources);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should exit with the generated source-pack value",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_source_pack_nested_flow_calls_are_name_independent() {
    for case in generated_x86_nested_source_pack_flow_cases() {
        let bytes = compile_source_pack(case.name, case.sources);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should exit with the generated nested source-pack value",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_source_pack_call_argument_expressions_are_name_independent() {
    for case in generated_x86_call_arg_expr_cases() {
        let bytes = compile_source_pack(case.name, case.sources);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should exit with call arguments evaluated from local expression nodes",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_regalloc_chunk_boundary_fails_closed_without_fallback_artifact() {
    for case in generated_x86_regalloc_chunk_boundary_cases() {
        let name = case.name;
        let source = case.source;
        let err = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect_err("regalloc should fail closed when recorded chunks do not cover value defs");

        match err {
            CompileError::GpuCodegen(message) => {
                assert!(
                    message.contains("virtual register allocation failure"),
                    "regalloc chunk overflow should fail closed before returning ELF bytes: {message}"
                );
            }
            CompileError::Diagnostic(diagnostic) => {
                panic!(
                    "expected record-level regalloc rejection, got source diagnostic: {}",
                    diagnostic.render()
                )
            }
            other => panic!("expected x86 regalloc rejection, got {other:?}"),
        }
    }
}

#[test]
fn generated_x86_call_abi_rejections_are_name_independent() {
    for case in generated_x86_rejection_cases() {
        expect_lnc0017_x86_diagnostic(case.name, case.source);
    }
}

#[test]
fn generated_x86_loop_contained_call_rejections_are_name_independent() {
    for case in generated_x86_loop_contained_call_cases() {
        let name = case.name;
        let source = case.source;
        let err = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect_err("loop-contained calls should fail closed until x86 lowering supports them");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                let message = diagnostic.render();
                assert_eq!(
                    diagnostic.code, "LNC0017",
                    "loop-contained call rejection should use the stable backend diagnostic: {message}"
                );
                assert!(
                    diagnostic
                        .message
                        .contains("unsupported x86 loop-contained call")
                        && message.contains("native x86 backend"),
                    "diagnostic should identify the native x86 loop-call boundary: {message}"
                );
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("x86 diagnostic should include a primary source label");
                let source_line = label
                    .source_line
                    .as_deref()
                    .expect("x86 diagnostic should include the source line");
                assert_eq!(
                    source_line,
                    format!("        value = {name}(value);"),
                    "diagnostic should include the loop-contained call line: {message}"
                );
                let call_start_column = source_line
                    .find(name)
                    .map(|offset| offset + 1)
                    .expect("fixture should contain the callee name");
                let call_end_column = source_line
                    .find(");")
                    .map(|offset| offset + 2)
                    .expect("fixture should contain the end of the call expression");
                assert!(
                    (call_start_column..=call_end_column).contains(&label.column),
                    "diagnostic should point at the loop-contained call expression: {message}"
                );
            }
            CompileError::GpuCodegen(message) => {
                panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
            }
            other => panic!("expected x86 diagnostic rejection, got {other:?}"),
        }
    }
}

#[test]
fn generated_x86_loop_let_initializer_call_rejections_are_name_independent() {
    for case in generated_x86_loop_let_initializer_call_cases() {
        let name = case.name;
        let source = case.source;
        let err = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect_err("loop-contained let initializer calls should fail through x86 status");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                let message = diagnostic.render();
                assert_eq!(
                    diagnostic.code, "LNC0017",
                    "let-initializer loop call rejection should use the stable backend diagnostic: {message}"
                );
                assert!(
                    diagnostic
                        .message
                        .contains("unsupported x86 loop-contained call")
                        && message.contains("native x86 backend"),
                    "diagnostic should identify the native x86 loop-call boundary: {message}"
                );
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("x86 diagnostic should include a primary source label");
                let source_line = label
                    .source_line
                    .as_deref()
                    .expect("x86 diagnostic should include the source line");
                assert!(
                    source_line.contains("let ") && source_line.contains("(value);"),
                    "diagnostic should include the loop-contained let initializer call: {message}"
                );
                let call_start_column = source_line
                    .find("= ")
                    .map(|offset| offset + 3)
                    .expect("fixture should contain the initializer expression");
                let call_end_column = source_line
                    .find(");")
                    .map(|offset| offset + 2)
                    .expect("fixture should contain the end of the call expression");
                assert!(
                    (call_start_column..=call_end_column).contains(&label.column),
                    "diagnostic should point into the initializer call expression: {message}"
                );
            }
            CompileError::GpuCodegen(message) => {
                panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
            }
            other => panic!("expected x86 diagnostic rejection, got {other:?}"),
        }
    }
}

#[test]
fn generated_x86_postfix_rejections_are_name_and_operator_independent() {
    for case in generated_x86_postfix_rejection_cases() {
        let name = case.name;
        let expected_operator = if case.source.contains("++") {
            "++"
        } else {
            "--"
        };
        let source = case.source;
        let err = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect_err("postfix inc/dec should fail closed until x86 lowering supports them");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                let message = diagnostic.render();
                assert_eq!(
                    diagnostic.code, "LNC0017",
                    "postfix rejection should use the stable backend diagnostic: {message}"
                );
                assert_eq!(
                    diagnostic.category, "native codegen",
                    "postfix rejection should stay in the public native-codegen diagnostic category: {message}"
                );
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("x86 diagnostic should include a primary source label");
                let source_line = label
                    .source_line
                    .as_deref()
                    .expect("x86 diagnostic should include the postfix source line");
                assert!(
                    label.line > 0 && label.column > 0 && source_line.contains(expected_operator),
                    "diagnostic should include a concrete source span: {message}"
                );
            }
            CompileError::GpuCodegen(message) => {
                panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
            }
            other => panic!("expected x86 diagnostic rejection, got {other:?}"),
        }
    }
}

#[test]
fn generated_x86_zero_divisor_rejections_are_name_and_shape_independent() {
    let cases = [
        (
            "helper_like_local_divisor",
            r#"
fn main() {
    let wrapping_mul: i32 = 0;
    return 12 / wrapping_mul;
}
"#
            .to_owned(),
            "    return 12 / wrapping_mul;",
        ),
        (
            "renamed_literal_mod_divisor",
            r#"
fn main() {
    return 12 % 0;
}
"#
            .to_owned(),
            "    return 12 % 0;",
        ),
    ];

    for (name, source, expected_line) in cases {
        let err = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect_err("known zero divisors should fail closed before native idiv can fault");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                let message = diagnostic.render();
                assert_eq!(
                    diagnostic.code, "LNC0017",
                    "zero-divisor rejection should use the stable backend diagnostic: {message}"
                );
                assert!(
                    diagnostic.message.contains("unsupported x86 zero divisor")
                        && message.contains("native x86 backend"),
                    "diagnostic should identify the native x86 zero-divisor boundary: {message}"
                );
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("x86 diagnostic should include a primary source label");
                assert_eq!(
                    label.source_line.as_deref(),
                    Some(expected_line),
                    "diagnostic should point at the zero-divisor expression: {message}"
                );
            }
            CompileError::GpuCodegen(message) => {
                panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
            }
            other => panic!("expected x86 diagnostic rejection, got {other:?}"),
        }
    }
}
