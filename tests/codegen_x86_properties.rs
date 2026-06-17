mod common;

use laniusc_compiler::compiler::{
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

struct GeneratedX86ShortCircuitRejectionCase {
    name: &'static str,
    source: String,
    expected_line: String,
    callee: &'static str,
}

struct GeneratedX86ShortCircuitTrappingRejectionCase {
    name: &'static str,
    source: String,
    expected_line: String,
    operand_fragment: String,
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

struct GeneratedX86SameModuleCallArgExprNames {
    callee: &'static str,
    first: &'static str,
    second: &'static str,
    third: &'static str,
    fourth: &'static str,
    local_a: &'static str,
    local_b: &'static str,
}

struct GeneratedX86NestedCallArgNames {
    module_path: &'static str,
    mix: &'static str,
    adjust: &'static str,
    nudge: &'static str,
    first: &'static str,
    second: &'static str,
    third: &'static str,
    fourth: &'static str,
    fifth: &'static str,
    sixth: &'static str,
    local_a: &'static str,
    local_b: &'static str,
}

struct GeneratedX86AggregateReturnNames {
    callee: &'static str,
    left: &'static str,
    right: &'static str,
    values: &'static str,
    first_local: &'static str,
    second_local: &'static str,
    result: &'static str,
}

struct GeneratedX86LoopBranchNames {
    total: &'static str,
    cursor: &'static str,
    limit: &'static str,
}

struct GeneratedX86ForArrayNames {
    values: &'static str,
    item: &'static str,
    total: &'static str,
}

struct GeneratedX86ForArrayCallControlNames {
    module_path: &'static str,
    adjust: &'static str,
    values: &'static str,
    item: &'static str,
    total: &'static str,
    term: &'static str,
}

struct GeneratedX86BoolOpNames {
    left: &'static str,
    right: &'static str,
}

struct GeneratedX86MutualRecursionNames {
    even: &'static str,
    odd: &'static str,
    parameter: &'static str,
}

struct GeneratedX86MethodLoopNames {
    module_path: &'static str,
    range_type: &'static str,
    make: &'static str,
    contains: &'static str,
    range: &'static str,
    value: &'static str,
    total: &'static str,
}

struct GeneratedX86EnumMatchNames {
    module_path: &'static str,
    enum_type: &'static str,
    some_variant: &'static str,
    none_variant: &'static str,
    choose: &'static str,
    score: &'static str,
    flag: &'static str,
    payload: &'static str,
    matched: &'static str,
    inner: &'static str,
    hit: &'static str,
    miss: &'static str,
}

struct GeneratedX86NestedLoopCallNames {
    module_path: &'static str,
    combine: &'static str,
    fold: &'static str,
    row: &'static str,
    column: &'static str,
    total: &'static str,
    limit: &'static str,
}

struct GeneratedX86ImportedAggregateLoopNames {
    module_path: &'static str,
    pair_type: &'static str,
    make_pair: &'static str,
    score: &'static str,
    left_field: &'static str,
    right_field: &'static str,
    row: &'static str,
    total: &'static str,
    pair: &'static str,
}

struct GeneratedX86ParameterIndexedAssignmentNames {
    module_path: &'static str,
    rewrite: &'static str,
    values: &'static str,
    bias: &'static str,
    skip: &'static str,
    stop: &'static str,
    index: &'static str,
    total: &'static str,
    input: &'static str,
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

fn generated_x86_same_module_call_arg_expr(
    name: &'static str,
    names: GeneratedX86SameModuleCallArgExprNames,
    local_a_value: i32,
    local_b_value: i32,
) -> GeneratedX86Case {
    let expected_first = local_a_value - local_b_value;
    let expected_second = local_b_value - 2;
    let expected_third = local_a_value - 3;
    let expected_fourth = local_b_value - 1;
    let expected_exit =
        expected_first * 10 + expected_second * 3 + expected_third - expected_fourth;
    let source = format!(
        r#"
fn {callee}({first}: i32, {second}: i32, {third}: i32, {fourth}: i32) -> i32 {{
    return {first} * 10 + {second} * 3 + {third} - {fourth};
}}

fn main() {{
    let {local_a}: i32 = {local_a_value};
    let {local_b}: i32 = {local_b_value};
    return {callee}({local_a} - {local_b}, {local_b} - 2, {local_a} - 3, {local_b} - 1);
}}
"#,
        callee = names.callee,
        first = names.first,
        second = names.second,
        third = names.third,
        fourth = names.fourth,
        local_a = names.local_a,
        local_b = names.local_b,
        local_a_value = local_a_value,
        local_b_value = local_b_value,
    );

    GeneratedX86Case {
        name,
        source,
        expected_exit,
    }
}

fn generated_x86_same_module_call_arg_expr_cases() -> [GeneratedX86Case; 2] {
    [
        generated_x86_same_module_call_arg_expr(
            "helper_like_local_expr_call_args",
            GeneratedX86SameModuleCallArgExprNames {
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
        generated_x86_same_module_call_arg_expr(
            "renamed_local_expr_call_args",
            GeneratedX86SameModuleCallArgExprNames {
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

fn generated_x86_same_module_aggregate_return_call(
    name: &'static str,
    names: GeneratedX86AggregateReturnNames,
    first_value: i32,
    second_value: i32,
) -> GeneratedX86Case {
    let expected_exit = (first_value + 1) * 10 + (second_value - 1);
    let source = format!(
        r#"
fn {callee}({left}: i32, {right}: i32) -> [i32; 2] {{
    let {values}: [i32; 2] = [{left} + 1, {right} - 1];
    return {values};
}}

fn main() {{
    let {first_local}: i32 = {first_value};
    let {second_local}: i32 = {second_value};
    let {result}: [i32; 2] = {callee}({first_local}, {second_local});
    return {result}[0] * 10 + {result}[1];
}}
"#,
        callee = names.callee,
        left = names.left,
        right = names.right,
        values = names.values,
        first_local = names.first_local,
        second_local = names.second_local,
        result = names.result,
        first_value = first_value,
        second_value = second_value,
    );

    GeneratedX86Case {
        name,
        source,
        expected_exit,
    }
}

fn generated_x86_same_module_aggregate_return_call_cases() -> [GeneratedX86Case; 2] {
    [
        generated_x86_same_module_aggregate_return_call(
            "helper_like_aggregate_return_call",
            GeneratedX86AggregateReturnNames {
                callee: "wrapping_mul",
                left: "value",
                right: "rhs",
                values: "packed",
                first_local: "computed",
                second_local: "bias",
                result: "observed",
            },
            8,
            9,
        ),
        generated_x86_same_module_aggregate_return_call(
            "renamed_aggregate_return_call",
            GeneratedX86AggregateReturnNames {
                callee: "make_pair",
                left: "first",
                right: "second",
                values: "items",
                first_local: "left_input",
                second_local: "right_input",
                result: "pair",
            },
            4,
            12,
        ),
    ]
}

fn generated_x86_consecutive_call_case(
    name: &'static str,
    mix: &'static str,
    bump: &'static str,
    anchor: &'static str,
    left: &'static str,
    right: &'static str,
    bump_first: bool,
) -> GeneratedX86Case {
    let anchor_value = 11;
    let expected_exit = 1 * 7 + 2 * 5 + 3 * 3 + 4 + (anchor_value + 2) + anchor_value;
    let call_bindings = if bump_first {
        format!(
            "    let {right}: i32 = {bump}({anchor});\n    let {left}: i32 = {mix}(1, 2, 3, 4);",
            right = right,
            bump = bump,
            anchor = anchor,
            left = left,
            mix = mix,
        )
    } else {
        format!(
            "    let {left}: i32 = {mix}(1, 2, 3, 4);\n    let {right}: i32 = {bump}({anchor});",
            left = left,
            mix = mix,
            right = right,
            bump = bump,
            anchor = anchor,
        )
    };
    let source = format!(
        r#"
fn {mix}(first: i32, second: i32, third: i32, fourth: i32) -> i32 {{
    return first * 7 + second * 5 + third * 3 + fourth;
}}

fn {bump}(value: i32) -> i32 {{
    return value + 2;
}}

fn main() {{
    let {anchor}: i32 = {anchor_value};
{call_bindings}
    return {left} + {right} + {anchor};
}}
"#,
        mix = mix,
        bump = bump,
        anchor = anchor,
        anchor_value = anchor_value,
        call_bindings = call_bindings,
        left = left,
        right = right,
    );

    GeneratedX86Case {
        name,
        source,
        expected_exit,
    }
}

fn generated_x86_consecutive_call_cases() -> [GeneratedX86Case; 2] {
    [
        generated_x86_consecutive_call_case(
            "helper_like_consecutive_calls_keep_live_locals",
            "wrapping_mul",
            "wrapping_add",
            "value",
            "rhs",
            "sum",
            false,
        ),
        generated_x86_consecutive_call_case(
            "renamed_reordered_consecutive_calls_keep_live_locals",
            "combine_values",
            "advance_value",
            "seed",
            "first_result",
            "second_result",
            true,
        ),
    ]
}

fn mutual_recursion_parity_expected(mut value: i32, starts_even: bool) -> i32 {
    let mut is_even_function = starts_even;
    while value > 0 {
        value -= 1;
        is_even_function = !is_even_function;
    }
    i32::from(is_even_function)
}

fn generated_x86_mutual_recursion_case(
    name: &'static str,
    names: GeneratedX86MutualRecursionNames,
    left_value: i32,
    right_value: i32,
    odd_first: bool,
) -> GeneratedX86Case {
    let even_function = format!(
        r#"
fn {even}({parameter}: i32) -> i32 {{
    if ({parameter} <= 0) {{
        return 1;
    }}
    return {odd}({parameter} - 1);
}}
"#,
        even = names.even,
        odd = names.odd,
        parameter = names.parameter,
    );
    let odd_function = format!(
        r#"
fn {odd}({parameter}: i32) -> i32 {{
    if ({parameter} <= 0) {{
        return 0;
    }}
    return {even}({parameter} - 1);
}}
"#,
        even = names.even,
        odd = names.odd,
        parameter = names.parameter,
    );
    let functions = if odd_first {
        format!("{odd_function}\n{even_function}")
    } else {
        format!("{even_function}\n{odd_function}")
    };
    let source = format!(
        r#"
{functions}
fn main() {{
    return {even}({left_value}) * 10 + {odd}({right_value});
}}
"#,
        functions = functions,
        even = names.even,
        odd = names.odd,
        left_value = left_value,
        right_value = right_value,
    );

    GeneratedX86Case {
        name,
        source,
        expected_exit: mutual_recursion_parity_expected(left_value, true) * 10
            + mutual_recursion_parity_expected(right_value, false),
    }
}

fn generated_x86_mutual_recursion_cases() -> [GeneratedX86Case; 2] {
    [
        generated_x86_mutual_recursion_case(
            "helper_like_mutual_recursion_forward_first",
            GeneratedX86MutualRecursionNames {
                even: "wrapping_mul",
                odd: "wrapping_add",
                parameter: "value",
            },
            6,
            7,
            false,
        ),
        generated_x86_mutual_recursion_case(
            "renamed_mutual_recursion_reverse_order",
            GeneratedX86MutualRecursionNames {
                even: "is_even_step",
                odd: "is_odd_step",
                parameter: "remaining",
            },
            4,
            6,
            true,
        ),
    ]
}

fn loop_branch_reference_expected(seed: i32, step: i32, threshold: i32) -> i32 {
    let mut total = seed;
    let mut cursor = 0;
    while cursor < 3 {
        if total + cursor > threshold {
            total += step + cursor;
        } else {
            total += step - cursor;
        }
        cursor += 1;
    }
    total
}

fn generated_x86_loop_branch_reference_case(
    name: &'static str,
    names: GeneratedX86LoopBranchNames,
    seed: i32,
    step: i32,
    threshold: i32,
) -> GeneratedX86Case {
    let source = format!(
        r#"
fn main() {{
    let {total}: i32 = {seed};
    let {cursor}: i32 = 0;
    let {limit}: i32 = {threshold};
    while ({cursor} < 3) {{
        if (({total} + {cursor}) > {limit}) {{
            {total} += {step} + {cursor};
        }} else {{
            {total} += {step} - {cursor};
        }}
        {cursor} += 1;
    }}
    return {total};
}}
"#,
        total = names.total,
        cursor = names.cursor,
        limit = names.limit,
        seed = seed,
        step = step,
        threshold = threshold,
    );

    GeneratedX86Case {
        name,
        source,
        expected_exit: loop_branch_reference_expected(seed, step, threshold),
    }
}

fn generated_x86_loop_branch_reference_cases() -> [GeneratedX86Case; 3] {
    [
        generated_x86_loop_branch_reference_case(
            "loop_branch_reference_low_threshold",
            GeneratedX86LoopBranchNames {
                total: "wrapping_mul",
                cursor: "value",
                limit: "rhs",
            },
            0,
            3,
            2,
        ),
        generated_x86_loop_branch_reference_case(
            "loop_branch_reference_high_threshold",
            GeneratedX86LoopBranchNames {
                total: "total",
                cursor: "index",
                limit: "limit",
            },
            5,
            4,
            50,
        ),
        generated_x86_loop_branch_reference_case(
            "loop_branch_reference_crosses_threshold",
            GeneratedX86LoopBranchNames {
                total: "observed",
                cursor: "cursor",
                limit: "cutoff",
            },
            8,
            2,
            9,
        ),
    ]
}

fn for_array_reference_expected(
    values: [i32; 6],
    seed: i32,
    skip: i32,
    stop: i32,
    scale: i32,
    bias: i32,
) -> i32 {
    let mut total = seed;
    for value in values {
        if value == skip {
            continue;
        }
        if value == stop {
            break;
        }
        total += value * scale + bias;
    }
    total
}

fn generated_x86_for_array_reference_case(
    name: &'static str,
    names: GeneratedX86ForArrayNames,
    values: [i32; 6],
    seed: i32,
    skip: i32,
    stop: i32,
    scale: i32,
    bias: i32,
) -> GeneratedX86Case {
    let values_literal = values
        .into_iter()
        .map(|value| value.to_string())
        .collect::<Vec<_>>()
        .join(", ");
    let source = format!(
        r#"
fn main() {{
    let {values}: [i32; 6] = [{values_literal}];
    let {total}: i32 = {seed};
    for {item} in {values} {{
        if ({item} == {skip}) {{
            continue;
        }}
        if ({item} == {stop}) {{
            break;
        }}
        {total} += {item} * {scale} + {bias};
    }}
    return {total};
}}
"#,
        values = names.values,
        total = names.total,
        item = names.item,
        values_literal = values_literal,
        seed = seed,
        skip = skip,
        stop = stop,
        scale = scale,
        bias = bias,
    );

    GeneratedX86Case {
        name,
        source,
        expected_exit: for_array_reference_expected(values, seed, skip, stop, scale, bias),
    }
}

fn generated_x86_for_array_reference_cases() -> [GeneratedX86Case; 2] {
    [
        generated_x86_for_array_reference_case(
            "for_array_reference_helper_like_names",
            GeneratedX86ForArrayNames {
                values: "wrapping_mul",
                item: "value",
                total: "rhs",
            },
            [1, 2, 3, 4, 5, 6],
            0,
            2,
            5,
            1,
            0,
        ),
        generated_x86_for_array_reference_case(
            "for_array_reference_renamed_weighted_values",
            GeneratedX86ForArrayNames {
                values: "numbers",
                item: "entry",
                total: "observed",
            },
            [3, 1, 4, 2, 5, 7],
            1,
            4,
            7,
            2,
            1,
        ),
    ]
}

fn for_array_call_control_reference_expected(
    values: [i32; 6],
    seed: i32,
    skip: i32,
    stop: i32,
    scale: i32,
    bias: i32,
) -> i32 {
    let mut total = seed;
    for value in values {
        if value == skip {
            continue;
        }
        if value == stop {
            break;
        }
        let term = value * scale + bias;
        if (term & 1) == 0 {
            total += term;
        } else {
            total += term + 1;
        }
    }
    total
}

fn generated_x86_source_pack_for_array_call_control_case(
    name: &'static str,
    names: GeneratedX86ForArrayCallControlNames,
    values: [i32; 6],
    seed: i32,
    skip: i32,
    stop: i32,
    scale: i32,
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

pub fn {adjust}(value: i32, scale: i32, bias: i32) -> i32 {{
    return value * scale + bias;
}}
"#,
            module_path = names.module_path,
            adjust = names.adjust,
        ),
        format!(
            r#"
module app::main;

import {module_path};

fn main() {{
    let {values}: [i32; 6] = [{values_literal}];
    let {total}: i32 = {seed};
    for {item} in {values} {{
        if ({item} == {skip}) {{
            continue;
        }}
        if ({item} == {stop}) {{
            break;
        }}
        let {term}: i32 = {module_path}::{adjust}({item}, {scale}, {bias});
        if (({term} & 1) == 0) {{
            {total} += {term};
        }} else {{
            {total} += {term} + 1;
        }}
    }}
    return {total};
}}
"#,
            module_path = names.module_path,
            adjust = names.adjust,
            values = names.values,
            total = names.total,
            item = names.item,
            term = names.term,
            values_literal = values_literal,
            seed = seed,
            skip = skip,
            stop = stop,
            scale = scale,
            bias = bias,
        ),
    ];

    GeneratedX86SourcePackCase {
        name,
        sources,
        expected_exit: for_array_call_control_reference_expected(
            values, seed, skip, stop, scale, bias,
        ),
    }
}

fn generated_x86_source_pack_for_array_call_control_cases() -> [GeneratedX86SourcePackCase; 2] {
    [
        generated_x86_source_pack_for_array_call_control_case(
            "source_pack_for_array_call_control_helper_like_names",
            GeneratedX86ForArrayCallControlNames {
                module_path: "helpers::score",
                adjust: "wrapping_mul",
                values: "value",
                item: "rhs",
                total: "sum",
                term: "computed",
            },
            [1, 2, 3, 4, 5, 6],
            0,
            2,
            5,
            2,
            1,
        ),
        generated_x86_source_pack_for_array_call_control_case(
            "source_pack_for_array_call_control_renamed_values",
            GeneratedX86ForArrayCallControlNames {
                module_path: "analysis::score",
                adjust: "score_entry",
                values: "numbers",
                item: "entry",
                total: "observed",
                term: "weighted",
            },
            [4, 1, 6, 2, 7, 3],
            3,
            6,
            7,
            3,
            -1,
        ),
    ]
}

fn bool_op_reference_expected(left: bool, right: bool, operator: &'static str) -> i32 {
    let result = match operator {
        "&&" => left && right,
        "||" => left || right,
        other => panic!("unsupported generated bool operator {other}"),
    };
    i32::from(result)
}

fn generated_x86_bool_op_reference_case(
    name: &'static str,
    names: GeneratedX86BoolOpNames,
    left_value: bool,
    right_value: bool,
    operator: &'static str,
) -> GeneratedX86Case {
    let source = format!(
        r#"
fn main() -> bool {{
    let {left}: bool = {left_value};
    let {right}: bool = {right_value};
    return {left} {operator} {right};
}}
"#,
        left = names.left,
        right = names.right,
        left_value = left_value,
        right_value = right_value,
        operator = operator,
    );

    GeneratedX86Case {
        name,
        source,
        expected_exit: bool_op_reference_expected(left_value, right_value, operator),
    }
}

fn generated_x86_bool_op_reference_cases() -> [GeneratedX86Case; 2] {
    [
        generated_x86_bool_op_reference_case(
            "bool_and_helper_like_names",
            GeneratedX86BoolOpNames {
                left: "wrapping_mul",
                right: "value",
            },
            true,
            false,
            "&&",
        ),
        generated_x86_bool_op_reference_case(
            "bool_or_renamed_names",
            GeneratedX86BoolOpNames {
                left: "observed",
                right: "ready",
            },
            false,
            true,
            "||",
        ),
    ]
}

fn source_pack_method_loop_reference_expected(
    start: i32,
    end: i32,
    initial: i32,
    step: i32,
    scale: i32,
    bias: i32,
) -> i32 {
    let mut value = initial;
    let mut total = 0;
    while value >= start && value < end {
        total += value * scale + bias;
        value += step;
    }
    total
}

fn generated_x86_source_pack_method_loop_reference_case(
    name: &'static str,
    names: GeneratedX86MethodLoopNames,
    start: i32,
    end: i32,
    initial: i32,
    step: i32,
    scale: i32,
    bias: i32,
) -> GeneratedX86SourcePackCase {
    let sources = vec![
        format!(
            r#"
module {module_path};

pub struct {range_type} {{
    start: i32,
    end: i32,
}}

pub fn {make}(start: i32, end: i32) -> {range_type} {{
    return {range_type} {{ start: start, end: end }};
}}

pub impl {range_type} {{
    pub fn {contains}(self, candidate: i32) -> bool {{
        return candidate >= self.start && candidate < self.end;
    }}
}}
"#,
            module_path = names.module_path,
            range_type = names.range_type,
            make = names.make,
            contains = names.contains,
        ),
        format!(
            r#"
module app::main;

import {module_path};

fn main() -> i32 {{
    let {range}: {module_path}::{range_type} = {module_path}::{make}({start}, {end});
    let {value}: i32 = {initial};
    let {total}: i32 = 0;
    while ({range}.{contains}({value})) {{
        {total} += {value} * {scale} + {bias};
        {value} += {step};
    }}
    return {total};
}}
"#,
            module_path = names.module_path,
            range_type = names.range_type,
            make = names.make,
            contains = names.contains,
            range = names.range,
            value = names.value,
            total = names.total,
            start = start,
            end = end,
            initial = initial,
            step = step,
            scale = scale,
            bias = bias,
        ),
    ];

    GeneratedX86SourcePackCase {
        name,
        sources,
        expected_exit: source_pack_method_loop_reference_expected(
            start, end, initial, step, scale, bias,
        ),
    }
}

fn generated_x86_source_pack_method_loop_reference_cases() -> [GeneratedX86SourcePackCase; 2] {
    [
        generated_x86_source_pack_method_loop_reference_case(
            "source_pack_method_loop_helper_like_names",
            GeneratedX86MethodLoopNames {
                module_path: "helpers::range",
                range_type: "Range",
                make: "wrapping_mul",
                contains: "contains",
                range: "value",
                value: "rhs",
                total: "sum",
            },
            0,
            4,
            0,
            1,
            2,
            1,
        ),
        generated_x86_source_pack_method_loop_reference_case(
            "source_pack_method_loop_renamed_names",
            GeneratedX86MethodLoopNames {
                module_path: "geometry::window",
                range_type: "Window",
                make: "build_window",
                contains: "covers",
                range: "window",
                value: "cursor",
                total: "observed",
            },
            2,
            9,
            3,
            2,
            1,
            4,
        ),
    ]
}

fn enum_match_reference_expected(
    first_flag: bool,
    first_value: i32,
    second_flag: bool,
    second_value: i32,
    payload_offset: i32,
    none_score: i32,
) -> i32 {
    let score = |flag: bool, value: i32| -> i32 {
        if flag {
            value + payload_offset
        } else {
            none_score
        }
    };
    score(first_flag, first_value) * 10 + score(second_flag, second_value)
}

fn generated_x86_source_pack_enum_match_case(
    name: &'static str,
    names: GeneratedX86EnumMatchNames,
    first_flag: bool,
    first_value: i32,
    second_flag: bool,
    second_value: i32,
    payload_offset: i32,
    none_score: i32,
) -> GeneratedX86SourcePackCase {
    let sources = vec![
        format!(
            r#"
module {module_path};

pub enum {enum_type} {{
    {some_variant}(i32),
    {none_variant},
}}

pub fn {choose}({flag}: bool, {payload}: i32) -> {enum_type} {{
    if ({flag}) {{
        return {some_variant}({payload});
    }}
    return {none_variant};
}}

pub fn {score}({matched}: {enum_type}) -> i32 {{
    return match ({matched}) {{
        {some_variant}({inner}) -> {inner} + {payload_offset},
        {none_variant} -> {none_score},
    }};
}}
"#,
            module_path = names.module_path,
            enum_type = names.enum_type,
            some_variant = names.some_variant,
            none_variant = names.none_variant,
            choose = names.choose,
            flag = names.flag,
            payload = names.payload,
            score = names.score,
            matched = names.matched,
            inner = names.inner,
            payload_offset = payload_offset,
            none_score = none_score,
        ),
        format!(
            r#"
module app::main;

import {module_path};

fn main() -> i32 {{
    let {hit}: {module_path}::{enum_type} = {module_path}::{choose}({first_flag}, {first_value});
    let {miss}: {module_path}::{enum_type} = {module_path}::{choose}({second_flag}, {second_value});
    return {module_path}::{score}({hit}) * 10 + {module_path}::{score}({miss});
}}
"#,
            module_path = names.module_path,
            enum_type = names.enum_type,
            choose = names.choose,
            score = names.score,
            hit = names.hit,
            miss = names.miss,
            first_flag = first_flag,
            first_value = first_value,
            second_flag = second_flag,
            second_value = second_value,
        ),
    ];

    GeneratedX86SourcePackCase {
        name,
        sources,
        expected_exit: enum_match_reference_expected(
            first_flag,
            first_value,
            second_flag,
            second_value,
            payload_offset,
            none_score,
        ),
    }
}

fn generated_x86_source_pack_enum_match_cases() -> [GeneratedX86SourcePackCase; 2] {
    [
        generated_x86_source_pack_enum_match_case(
            "source_pack_enum_match_helper_like_names",
            GeneratedX86EnumMatchNames {
                module_path: "core::option",
                enum_type: "OptionI32",
                some_variant: "Some",
                none_variant: "None",
                choose: "wrapping_mul",
                score: "wrapping_add",
                flag: "value",
                payload: "rhs",
                matched: "observed",
                inner: "sum",
                hit: "computed",
                miss: "fallback",
            },
            true,
            4,
            false,
            9,
            2,
            5,
        ),
        generated_x86_source_pack_enum_match_case(
            "source_pack_enum_match_renamed_names",
            GeneratedX86EnumMatchNames {
                module_path: "domain::choice",
                enum_type: "Decision",
                some_variant: "Selected",
                none_variant: "Empty",
                choose: "choose_value",
                score: "score_choice",
                flag: "is_present",
                payload: "amount",
                matched: "decision",
                inner: "payload",
                hit: "left",
                miss: "right",
            },
            true,
            3,
            false,
            8,
            4,
            6,
        ),
    ]
}

fn nested_loop_call_reference_expected(limit: i32, seed: i32, step: i32) -> i32 {
    let mut row = 0;
    let mut total = seed;
    while row < limit {
        let mut column = 0;
        while column < row {
            total = total + column * step + row;
            column += 1;
        }
        row += 1;
    }
    total
}

fn generated_x86_source_pack_nested_loop_call_case(
    name: &'static str,
    names: GeneratedX86NestedLoopCallNames,
    limit_value: i32,
    seed: i32,
    step: i32,
) -> GeneratedX86SourcePackCase {
    let sources = vec![
        format!(
            r#"
module {module_path};

pub fn {combine}(total: i32, row: i32, column: i32, step: i32) -> i32 {{
    return total + column * step + row;
}}

pub fn {fold}({limit}: i32, seed: i32, step: i32) -> i32 {{
    let {row}: i32 = 0;
    let {total}: i32 = seed;
    while ({row} < {limit}) {{
        let {column}: i32 = 0;
        while ({column} < {row}) {{
            {total} = {combine}({total}, {row}, {column}, step);
            {column} += 1;
        }}
        {row} += 1;
    }}
    return {total};
}}
"#,
            module_path = names.module_path,
            combine = names.combine,
            fold = names.fold,
            row = names.row,
            column = names.column,
            total = names.total,
            limit = names.limit,
        ),
        format!(
            r#"
module app::main;

import {module_path};

fn main() -> i32 {{
    return {module_path}::{fold}({limit_value}, {seed}, {step});
}}
"#,
            module_path = names.module_path,
            fold = names.fold,
            limit_value = limit_value,
            seed = seed,
            step = step,
        ),
    ];

    GeneratedX86SourcePackCase {
        name,
        sources,
        expected_exit: nested_loop_call_reference_expected(limit_value, seed, step),
    }
}

fn generated_x86_source_pack_nested_loop_call_cases() -> [GeneratedX86SourcePackCase; 2] {
    [
        generated_x86_source_pack_nested_loop_call_case(
            "source_pack_nested_loop_call_helper_like_names",
            GeneratedX86NestedLoopCallNames {
                module_path: "helpers::nested",
                combine: "wrapping_mul",
                fold: "wrapping_add",
                row: "value",
                column: "rhs",
                total: "sum",
                limit: "mask",
            },
            4,
            1,
            2,
        ),
        generated_x86_source_pack_nested_loop_call_case(
            "source_pack_nested_loop_call_renamed_names",
            GeneratedX86NestedLoopCallNames {
                module_path: "analysis::fold",
                combine: "accumulate_cell",
                fold: "fold_triangle",
                row: "row",
                column: "column",
                total: "observed",
                limit: "limit",
            },
            5,
            2,
            1,
        ),
    ]
}

fn imported_aggregate_loop_expected(limit: i32, seed: i32) -> i32 {
    let mut row = 0;
    let mut total = 0;
    while row < limit {
        let left = seed + row;
        let right = seed + limit - row;
        total += left * 10 + right;
        row += 1;
    }
    total
}

fn generated_x86_source_pack_imported_aggregate_loop_case(
    name: &'static str,
    names: GeneratedX86ImportedAggregateLoopNames,
    limit_value: i32,
    seed: i32,
) -> GeneratedX86SourcePackCase {
    let sources = vec![
        format!(
            r#"
module {module_path};

pub struct {pair_type} {{
    {left_field}: i32,
    {right_field}: i32,
}}

pub fn {make_pair}({left_field}: i32, {right_field}: i32) -> {pair_type} {{
    return {pair_type} {{ {left_field}: {left_field}, {right_field}: {right_field} }};
}}

pub fn {score}({pair}: {pair_type}) -> i32 {{
    return {pair}.{left_field} * 10 + {pair}.{right_field};
}}
"#,
            module_path = names.module_path,
            pair_type = names.pair_type,
            make_pair = names.make_pair,
            score = names.score,
            left_field = names.left_field,
            right_field = names.right_field,
            pair = names.pair,
        ),
        format!(
            r#"
module app::main;

import {module_path};

fn main() -> i32 {{
    let {row}: i32 = 0;
    let {total}: i32 = 0;
    while ({row} < {limit_value}) {{
        let {pair}: {module_path}::{pair_type} = {module_path}::{make_pair}({seed} + {row}, {seed} + {limit_value} - {row});
        {total} += {module_path}::{score}({pair});
        {row} += 1;
    }}
    return {total};
}}
"#,
            module_path = names.module_path,
            pair_type = names.pair_type,
            make_pair = names.make_pair,
            score = names.score,
            row = names.row,
            total = names.total,
            pair = names.pair,
            limit_value = limit_value,
            seed = seed,
        ),
    ];

    GeneratedX86SourcePackCase {
        name,
        sources,
        expected_exit: imported_aggregate_loop_expected(limit_value, seed),
    }
}

fn generated_x86_source_pack_imported_aggregate_loop_cases() -> [GeneratedX86SourcePackCase; 2] {
    [
        generated_x86_source_pack_imported_aggregate_loop_case(
            "source_pack_imported_aggregate_loop_helper_like_names",
            GeneratedX86ImportedAggregateLoopNames {
                module_path: "core::i32",
                pair_type: "WrappingMul",
                make_pair: "wrapping_mul",
                score: "wrapping_add",
                left_field: "value",
                right_field: "rhs",
                row: "shift",
                total: "sum",
                pair: "computed",
            },
            3,
            2,
        ),
        generated_x86_source_pack_imported_aggregate_loop_case(
            "source_pack_imported_aggregate_loop_renamed_names",
            GeneratedX86ImportedAggregateLoopNames {
                module_path: "helpers::pairs",
                pair_type: "Pair",
                make_pair: "make_pair",
                score: "score_pair",
                left_field: "left",
                right_field: "right",
                row: "index",
                total: "total",
                pair: "pair",
            },
            4,
            1,
        ),
    ]
}

fn parameter_indexed_assignment_expected(
    mut values: [i32; 4],
    bias: i32,
    skip: i32,
    stop: i32,
) -> i32 {
    let mut index = 0usize;
    let mut total = 0;
    while index < values.len() {
        if values[index] == skip {
            values[index] += bias;
            index += 1;
            continue;
        }

        values[index] += index as i32;
        total += values[index];
        if values[index] == stop {
            break;
        }
        index += 1;
    }
    total + values[0] * 3 + values[3]
}

fn generated_x86_source_pack_parameter_indexed_assignment_case(
    name: &'static str,
    names: GeneratedX86ParameterIndexedAssignmentNames,
    values: [i32; 4],
    bias: i32,
    skip: i32,
    stop: i32,
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

pub fn {rewrite}({values}: [i32; 4], {bias}: i32, {skip}: i32, {stop}: i32) -> i32 {{
    let {index}: i32 = 0;
    let {total}: i32 = 0;
    while ({index} < 4) {{
        if ({values}[{index}] == {skip}) {{
            {values}[{index}] += {bias};
            {index} += 1;
            continue;
        }}
        {values}[{index}] += {index};
        {total} += {values}[{index}];
        if ({values}[{index}] == {stop}) {{
            break;
        }}
        {index} += 1;
    }}
    return {total} + {values}[0] * 3 + {values}[3];
}}
"#,
            module_path = names.module_path,
            rewrite = names.rewrite,
            values = names.values,
            bias = names.bias,
            skip = names.skip,
            stop = names.stop,
            index = names.index,
            total = names.total,
        ),
        format!(
            r#"
module app::main;

import {module_path};

fn main() -> i32 {{
    let {input}: [i32; 4] = [{values_literal}];
    return {module_path}::{rewrite}({input}, {bias_value}, {skip_value}, {stop_value});
}}
"#,
            module_path = names.module_path,
            rewrite = names.rewrite,
            input = names.input,
            values_literal = values_literal,
            bias_value = bias,
            skip_value = skip,
            stop_value = stop,
        ),
    ];

    GeneratedX86SourcePackCase {
        name,
        sources,
        expected_exit: parameter_indexed_assignment_expected(values, bias, skip, stop),
    }
}

fn generated_x86_source_pack_parameter_indexed_assignment_cases() -> [GeneratedX86SourcePackCase; 2]
{
    [
        generated_x86_source_pack_parameter_indexed_assignment_case(
            "source_pack_parameter_indexed_assignment_helper_like_names",
            GeneratedX86ParameterIndexedAssignmentNames {
                module_path: "core::i32",
                rewrite: "wrapping_add",
                values: "value",
                bias: "rhs",
                skip: "shift",
                stop: "mask",
                index: "cursor",
                total: "sum",
                input: "computed",
            },
            [1, 3, 4, 5],
            2,
            3,
            6,
        ),
        generated_x86_source_pack_parameter_indexed_assignment_case(
            "source_pack_parameter_indexed_assignment_renamed_values",
            GeneratedX86ParameterIndexedAssignmentNames {
                module_path: "helpers::arrays",
                rewrite: "rewrite_values",
                values: "items",
                bias: "delta",
                skip: "skip_value",
                stop: "stop_value",
                index: "cursor",
                total: "observed",
                input: "numbers",
            },
            [2, 5, 1, 4],
            3,
            5,
            99,
        ),
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

fn generated_x86_nested_call_arg_source_pack(
    name: &'static str,
    names: GeneratedX86NestedCallArgNames,
    local_a_value: i32,
    local_b_value: i32,
    reverse_helper_declarations: bool,
) -> GeneratedX86SourcePackCase {
    let expected_first = local_a_value + 1;
    let expected_second = local_b_value + 2;
    let expected_third = local_a_value - 3;
    let expected_fourth = local_b_value;
    let expected_fifth = local_a_value - local_b_value - 4;
    let expected_sixth = local_a_value + local_b_value - 8;
    let expected_exit = expected_first
        + expected_second * 2
        + expected_third * 3
        + expected_fourth * 4
        + expected_fifth * 5
        + expected_sixth * 6;
    let adjust_decl = format!(
        r#"
pub fn {adjust}(value: i32, bias: i32) -> i32 {{
    return value + bias;
}}
"#,
        adjust = names.adjust,
    );

    let nudge_decl = format!(
        r#"
pub fn {nudge}(value: i32, bias: i32) -> i32 {{
    return value - bias;
}}
"#,
        nudge = names.nudge,
    );

    let mix_decl = format!(
        r#"
pub fn {mix}({first}: i32, {second}: i32, {third}: i32, {fourth}: i32, {fifth}: i32, {sixth}: i32) -> i32 {{
    return {first} + {second} * 2 + {third} * 3 + {fourth} * 4 + {fifth} * 5 + {sixth} * 6;
}}
"#,
        mix = names.mix,
        first = names.first,
        second = names.second,
        third = names.third,
        fourth = names.fourth,
        fifth = names.fifth,
        sixth = names.sixth,
    );
    let helper_declarations = if reverse_helper_declarations {
        format!("{mix_decl}{nudge_decl}{adjust_decl}")
    } else {
        format!("{adjust_decl}{nudge_decl}{mix_decl}")
    };
    let sources = vec![
        format!(
            r#"
module {module_path};
{helper_declarations}
"#,
            module_path = names.module_path,
            helper_declarations = helper_declarations,
        ),
        format!(
            r#"
module app::main;
import {module_path};
fn main() {{
    let {local_a}: i32 = {local_a_value};
    let {local_b}: i32 = {local_b_value};
    return {module_path}::{mix}({module_path}::{adjust}({local_a}, 1), {module_path}::{nudge}({local_b} + 4, 2), {local_a} - 3, {module_path}::{adjust}({local_b} - 1, 1), {module_path}::{nudge}({local_a} - {local_b}, 4), {module_path}::{adjust}({local_a} - 5, {local_b} - 3));
}}
"#,
            module_path = names.module_path,
            mix = names.mix,
            adjust = names.adjust,
            nudge = names.nudge,
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

fn generated_x86_nested_call_arg_cases() -> [GeneratedX86SourcePackCase; 3] {
    [
        generated_x86_nested_call_arg_source_pack(
            "source_pack_helper_like_nested_call_args",
            GeneratedX86NestedCallArgNames {
                module_path: "helpers::calls",
                mix: "wrapping_mul",
                adjust: "wrapping_add",
                nudge: "saturating_sub",
                first: "value",
                second: "rhs",
                third: "shift",
                fourth: "mask",
                fifth: "flags",
                sixth: "count",
                local_a: "computed",
                local_b: "bias",
            },
            9,
            5,
            false,
        ),
        generated_x86_nested_call_arg_source_pack(
            "source_pack_renamed_nested_call_args",
            GeneratedX86NestedCallArgNames {
                module_path: "analysis::calls",
                mix: "combine_weighted",
                adjust: "shift_value",
                nudge: "trim_value",
                first: "left",
                second: "right",
                third: "scale",
                fourth: "offset",
                fifth: "weight",
                sixth: "bonus",
                local_a: "observed",
                local_b: "delta",
            },
            6,
            3,
            false,
        ),
        generated_x86_nested_call_arg_source_pack(
            "source_pack_reordered_nested_call_args",
            GeneratedX86NestedCallArgNames {
                module_path: "routing::calls",
                mix: "collect_terms",
                adjust: "lift_value",
                nudge: "lower_value",
                first: "alpha",
                second: "beta",
                third: "gamma",
                fourth: "delta",
                fifth: "epsilon",
                sixth: "zeta",
                local_a: "seed",
                local_b: "offset",
            },
            7,
            4,
            true,
        ),
    ]
}

fn generated_x86_loop_contained_call(callee: &'static str) -> GeneratedX86Case {
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

    GeneratedX86Case {
        name: callee,
        source,
        expected_exit: 2,
    }
}

fn generated_x86_loop_contained_call_cases() -> [GeneratedX86Case; 2] {
    [
        generated_x86_loop_contained_call("wrapping_mul"),
        generated_x86_loop_contained_call("advance_value"),
    ]
}

fn generated_x86_loop_let_initializer_call(
    callee: &'static str,
    binding: &'static str,
) -> GeneratedX86Case {
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

    GeneratedX86Case {
        name: callee,
        source,
        expected_exit: 2,
    }
}

fn generated_x86_loop_let_initializer_call_cases() -> [GeneratedX86Case; 2] {
    [
        generated_x86_loop_let_initializer_call("advance_value", "next_value"),
        generated_x86_loop_let_initializer_call("compute_next", "observed"),
    ]
}

fn generated_x86_call_arg_count_rejection(
    name: &'static str,
    callee: &'static str,
    params: [&'static str; 7],
    local: &'static str,
) -> GeneratedX86RejectionCase {
    let source = format!(
        r#"
fn {callee}({p0}: i32, {p1}: i32, {p2}: i32, {p3}: i32, {p4}: i32, {p5}: i32, {p6}: i32) -> i32 {{
    return {p0} + {p1} + {p2} + {p3} + {p4} + {p5} + {p6};
}}

fn main() {{
    let {local}: i32 = 7;
    return {callee}(1, 2, 3, 4, 5, 6, {local});
}}
"#,
        callee = callee,
        p0 = params[0],
        p1 = params[1],
        p2 = params[2],
        p3 = params[3],
        p4 = params[4],
        p5 = params[5],
        p6 = params[6],
        local = local,
    );

    GeneratedX86RejectionCase { name, source }
}

fn generated_x86_call_arg_count_rejection_cases() -> [GeneratedX86RejectionCase; 2] {
    [
        generated_x86_call_arg_count_rejection(
            "helper_like_seven_arg_call",
            "wrapping_mul",
            ["value", "rhs", "shift", "mask", "spill", "extra", "last"],
            "observed",
        ),
        generated_x86_call_arg_count_rejection(
            "renamed_seven_arg_call",
            "combine_values",
            [
                "first", "second", "third", "fourth", "fifth", "sixth", "seventh",
            ],
            "total",
        ),
    ]
}

fn generated_x86_short_circuit_rhs_call_rejection(
    name: &'static str,
    callee: &'static str,
    value: &'static str,
    operator: &'static str,
    left_value: bool,
    rhs_value: i32,
) -> GeneratedX86ShortCircuitRejectionCase {
    let expected_line = format!("    return {value} {operator} {callee}({rhs_value});");
    let source = format!(
        r#"
fn {callee}(input: i32) -> bool {{
    return input > 0;
}}

fn main() -> bool {{
    let {value}: bool = {left_value};
{expected_line}
}}
"#,
        callee = callee,
        value = value,
        left_value = left_value,
        expected_line = expected_line,
    );

    GeneratedX86ShortCircuitRejectionCase {
        name,
        source,
        expected_line,
        callee,
    }
}

fn generated_x86_short_circuit_rhs_call_rejection_cases()
-> [GeneratedX86ShortCircuitRejectionCase; 2] {
    [
        generated_x86_short_circuit_rhs_call_rejection(
            "helper_like_and_rhs_call",
            "wrapping_mul",
            "value",
            "&&",
            false,
            1,
        ),
        generated_x86_short_circuit_rhs_call_rejection(
            "renamed_or_rhs_call",
            "is_ready",
            "observed",
            "||",
            true,
            2,
        ),
    ]
}

fn generated_x86_short_circuit_trapping_rejection(
    name: &'static str,
    function: &'static str,
    predicate: &'static str,
    parameter: &'static str,
    operator: &'static str,
    left_value: bool,
    rhs_expr: String,
    argument_value: i32,
) -> GeneratedX86ShortCircuitTrappingRejectionCase {
    let expected_line = format!("    return {predicate} {operator} ({rhs_expr});");
    let source = format!(
        r#"
fn {function}({parameter}: i32) -> bool {{
    let {predicate}: bool = {left_value};
{expected_line}
}}

fn main() -> bool {{
    return {function}({argument_value});
}}
"#,
        function = function,
        parameter = parameter,
        predicate = predicate,
        left_value = left_value,
        expected_line = expected_line,
        argument_value = argument_value,
    );

    GeneratedX86ShortCircuitTrappingRejectionCase {
        name,
        source,
        expected_line,
        operand_fragment: rhs_expr,
    }
}

fn generated_x86_short_circuit_trapping_rejection_cases()
-> [GeneratedX86ShortCircuitTrappingRejectionCase; 2] {
    [
        generated_x86_short_circuit_trapping_rejection(
            "helper_like_and_rhs_dynamic_divisor",
            "wrapping_mul",
            "value",
            "rhs",
            "&&",
            false,
            "(12 / rhs) == 0".to_owned(),
            0,
        ),
        generated_x86_short_circuit_trapping_rejection(
            "renamed_or_rhs_dynamic_shift_count",
            "check_ready",
            "observed",
            "amount",
            "||",
            true,
            "(1 << amount) == 0".to_owned(),
            32,
        ),
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

fn generated_x86_regalloc_chunk_boundary_cases() -> [GeneratedX86Case; 2] {
    const BINDING_COUNT: usize = 40;
    let expected_exit = (BINDING_COUNT - 1) as i32;
    [
        GeneratedX86Case {
            name: "regalloc_chunk_helper_like_value_defs",
            source: generated_x86_regalloc_chunk_boundary_source("wrapping_mul", BINDING_COUNT),
            expected_exit,
        },
        GeneratedX86Case {
            name: "regalloc_chunk_renamed_value_defs",
            source: generated_x86_regalloc_chunk_boundary_source("observed", BINDING_COUNT),
            expected_exit,
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
fn generated_x86_same_module_call_argument_expressions_are_name_independent() {
    for case in generated_x86_same_module_call_arg_expr_cases() {
        let bytes = compile_source(case.name, &case.source);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should exit with same-module call arguments evaluated from local expression nodes",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_same_module_aggregate_return_calls_are_name_independent() {
    for case in generated_x86_same_module_aggregate_return_call_cases() {
        let bytes = compile_source(case.name, &case.source);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should exit with the aggregate returned by the same-module helper",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_consecutive_calls_are_name_and_order_independent() {
    for case in generated_x86_consecutive_call_cases() {
        let bytes = compile_source(case.name, &case.source);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should preserve locals across consecutive helper calls",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_mutual_recursion_matches_reference_model() {
    for case in generated_x86_mutual_recursion_cases() {
        let bytes = compile_source(case.name, &case.source);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should match the Rust reference model for mutually recursive scalar calls",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_loop_branch_execution_matches_reference_model() {
    for case in generated_x86_loop_branch_reference_cases() {
        let bytes = compile_source(case.name, &case.source);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should match the Rust reference model for loop/branch state updates",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_for_array_control_flow_matches_reference_model() {
    for case in generated_x86_for_array_reference_cases() {
        let bytes = compile_source(case.name, &case.source);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should match the Rust reference model for array for-loop control flow",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_source_pack_for_array_call_control_matches_reference_model() {
    for case in generated_x86_source_pack_for_array_call_control_cases() {
        let bytes = compile_source_pack(case.name, case.sources);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should match the Rust reference model for imported calls guarded by for-loop control flow",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_bool_ops_execute_like_reference_model() {
    for case in generated_x86_bool_op_reference_cases() {
        let bytes = compile_source(case.name, &case.source);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should match the Rust reference model for boolean operator execution",
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
fn generated_x86_source_pack_nested_call_arguments_preserve_inner_callee_results() {
    for case in generated_x86_nested_call_arg_cases() {
        let bytes = compile_source_pack(case.name, case.sources);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should preserve mixed nested callee results across all six packed outer call argument positions",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_source_pack_method_loop_conditions_match_reference_model() {
    for case in generated_x86_source_pack_method_loop_reference_cases() {
        let bytes = compile_source_pack(case.name, case.sources);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should match the Rust reference model for imported method loop conditions",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_source_pack_enum_return_matches_match_reference_model() {
    for case in generated_x86_source_pack_enum_match_cases() {
        let bytes = compile_source_pack(case.name, case.sources);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should match the Rust reference model for imported enum returns and matches",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_source_pack_nested_loop_calls_match_reference_model() {
    for case in generated_x86_source_pack_nested_loop_call_cases() {
        let bytes = compile_source_pack(case.name, case.sources);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should match the Rust reference model for imported nested-loop helper calls",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_source_pack_imported_aggregate_loop_calls_match_reference_model() {
    for case in generated_x86_source_pack_imported_aggregate_loop_cases() {
        let bytes = compile_source_pack(case.name, case.sources);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should match the Rust reference model for imported aggregate-return calls in loops",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_source_pack_parameter_indexed_assignments_match_reference_model() {
    for case in generated_x86_source_pack_parameter_indexed_assignment_cases() {
        let bytes = compile_source_pack(case.name, case.sources);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should match the Rust reference model for imported parameter indexed assignments",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_direct_call_argument_count_rejections_are_name_independent() {
    for case in generated_x86_call_arg_count_rejection_cases() {
        let name = case.name;
        let source = case.source;
        let err = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect_err("seven-argument direct calls should exceed the SysV scalar register ABI");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                let message = diagnostic.render();
                assert_eq!(
                    diagnostic.code, "LNC0017",
                    "call-argument rejection should use the stable backend diagnostic: {message}"
                );
                assert_eq!(
                    diagnostic.category, "native codegen",
                    "call-argument rejection should stay in native codegen: {message}"
                );
                assert!(
                    diagnostic
                        .message
                        .contains("unsupported x86 call argument count")
                        && message.contains("native x86 backend"),
                    "diagnostic should identify the SysV scalar register boundary: {message}"
                );
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("x86 diagnostic should include a primary source label");
                let source_line = label
                    .source_line
                    .as_deref()
                    .expect("x86 diagnostic should include the direct-call source line");
                assert!(
                    label.line > 0
                        && label.column > 0
                        && source_line.trim_start().starts_with("return ")
                        && source_line.contains("(1, 2, 3, 4, 5, 6,"),
                    "diagnostic should point at the generated unsupported direct call: {message}"
                );
            }
            CompileError::GpuCodegen(message) => {
                panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
            }
            other => panic!("expected x86 call argument-count rejection, got {other:?}"),
        }
    }
}

#[test]
fn generated_x86_short_circuit_rhs_call_rejections_are_name_and_operator_independent() {
    for case in generated_x86_short_circuit_rhs_call_rejection_cases() {
        let name = case.name;
        let source = case.source;
        let err = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect_err("short-circuit RHS calls should fail until conditional call lowering exists");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                let message = diagnostic.render();
                assert_eq!(
                    diagnostic.code, "LNC0017",
                    "short-circuit call rejection should use the stable backend diagnostic: {message}"
                );
                assert_eq!(
                    diagnostic.category, "native codegen",
                    "short-circuit call rejection should stay in native codegen: {message}"
                );
                assert!(
                    diagnostic
                        .message
                        .contains("unsupported x86 short-circuit call operand")
                        && message.contains("native x86 backend"),
                    "diagnostic should identify the short-circuit call boundary: {message}"
                );
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("x86 diagnostic should include a primary source label");
                let source_line = label
                    .source_line
                    .as_deref()
                    .expect("x86 diagnostic should include the short-circuit source line");
                assert_eq!(
                    source_line, case.expected_line,
                    "diagnostic should point at the generated short-circuit expression: {message}"
                );
                let call_start_column = case
                    .expected_line
                    .find(case.callee)
                    .map(|column| column + 1)
                    .expect("fixture should contain the generated callee name");
                let call_end_column = case
                    .expected_line
                    .find(");")
                    .map(|column| column + 2)
                    .expect("fixture should contain the generated RHS call expression");
                assert!(
                    (call_start_column..=call_end_column).contains(&label.column),
                    "diagnostic column should fall inside the generated RHS call: {message}"
                );
            }
            CompileError::GpuCodegen(message) => {
                panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
            }
            other => panic!("expected x86 short-circuit call rejection, got {other:?}"),
        }
    }
}

#[test]
fn generated_x86_short_circuit_trapping_rejections_are_name_and_shape_independent() {
    for case in generated_x86_short_circuit_trapping_rejection_cases() {
        let name = case.name;
        let source = case.source;
        let err = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect_err("trap-sensitive RHS operands should fail until conditional lowering exists");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                let message = diagnostic.render();
                assert_eq!(
                    diagnostic.code, "LNC0017",
                    "short-circuit trapping rejection should use the stable backend diagnostic: {message}"
                );
                assert_eq!(
                    diagnostic.category, "native codegen",
                    "short-circuit trapping rejection should stay in native codegen: {message}"
                );
                assert!(
                    diagnostic
                        .message
                        .contains("unsupported x86 short-circuit trapping operand")
                        && message.contains("native x86 backend"),
                    "diagnostic should identify the conditional trap-lowering boundary: {message}"
                );
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("x86 diagnostic should include a primary source label");
                let source_line = label
                    .source_line
                    .as_deref()
                    .expect("x86 diagnostic should include the short-circuit source line");
                assert_eq!(
                    source_line, case.expected_line,
                    "diagnostic should point at the generated short-circuit expression: {message}"
                );
                let operand_start = case
                    .expected_line
                    .find(&case.operand_fragment)
                    .map(|column| column + 1)
                    .expect("fixture should contain the generated RHS operand");
                let operand_end = operand_start + case.operand_fragment.len();
                assert!(
                    (operand_start..=operand_end).contains(&label.column),
                    "diagnostic column should fall inside the generated RHS trapping operand: {message}"
                );
            }
            CompileError::GpuCodegen(message) => {
                panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
            }
            other => panic!("expected x86 short-circuit trapping rejection, got {other:?}"),
        }
    }
}

#[test]
fn generated_x86_regalloc_chunk_boundary_executes_across_recorded_capacity_span() {
    for case in generated_x86_regalloc_chunk_boundary_cases() {
        let bytes = compile_source(case.name, &case.source);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should execute across the compact regalloc value-def chunk boundary",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_loop_assignment_calls_are_name_independent() {
    for case in generated_x86_loop_contained_call_cases() {
        let bytes = compile_source(case.name, &case.source);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should execute the loop-body helper call",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_loop_let_initializer_calls_are_name_independent() {
    for case in generated_x86_loop_let_initializer_call_cases() {
        let bytes = compile_source(case.name, &case.source);
        assert_x86_64_elf_header(&bytes);

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(case.name, case.name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(case.expected_exit),
                "{} should execute the loop-body let-initializer helper call",
                case.name,
            );
        }

        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = case.expected_exit;
    }
}

#[test]
fn generated_x86_divisor_boundaries_are_name_and_shape_independent() {
    let runtime_trap_cases = [(
        "helper_like_local_divisor",
        r#"
fn main() {
    let wrapping_mul: i32 = 0;
    return 12 / wrapping_mul;
}
"#
        .to_owned(),
    )];

    for (name, source) in runtime_trap_cases {
        let bytes = compile_source(name, &source);
        assert_x86_64_elf_header(&bytes);
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(103),
                "generated zero divisors through mutable locals should use the x86 runtime trap"
            );
        }
    }

    let diagnostic_cases = [(
        "renamed_literal_mod_divisor",
        r#"
fn main() {
    return 12 % 0;
}
"#
        .to_owned(),
        "    return 12 % 0;",
    )];

    for (name, source, expected_line) in diagnostic_cases {
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
