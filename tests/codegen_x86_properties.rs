#![cfg(all(unix, target_arch = "x86_64"))]

mod common;

use laniusc::compiler::compile_source_to_x86_64_with_gpu_codegen;
use rand::{Rng, SeedableRng, rngs::StdRng};

const CASE_COUNT: usize = 8;

#[derive(Clone, Debug)]
struct GeneratedProgram {
    label: String,
    source: String,
    expected_status: i32,
}

#[test]
fn generated_x86_programs_are_name_and_shape_independent() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_7072_6f70);
    let mut cases = (0..CASE_COUNT)
        .map(|case_i| generated_program(&mut rng, case_i))
        .collect::<Vec<_>>();
    cases.push(generated_mod_program(&mut rng));
    cases.extend(generated_extended_binary_programs(&mut rng));
    cases.extend(generated_local_constant_chain_programs(&mut rng));
    cases.extend(generated_call_programs(&mut rng));
    cases.extend(generated_mutable_loop_programs(&mut rng));
    cases.extend(generated_nested_dependency_programs(&mut rng));
    cases.push(generated_bool_branch_program(&mut rng));
    cases.push(generated_loop_control_program(&mut rng));

    for case in cases {
        let source = case.source.clone();
        let bytes = common::run_gpu_codegen_with_timeout(
            &format!(
                "GPU x86 property compile {}\nsource:\n{}",
                case.label, case.source
            ),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .unwrap_or_else(|err| {
            panic!(
                "generated x86 case {} should compile\nsource:\n{}\nerror: {err}",
                case.label, case.source
            )
        });

        assert_eq!(&bytes[0..4], b"\x7fELF", "{} should emit ELF", case.label);
        let output = common::run_x86_64_elf_output(
            format!("generated x86 case {}", case.label),
            &format!("generated_x86_{}", sanitize_for_artifact(&case.label)),
            &bytes,
        );
        assert_eq!(
            output.status.code(),
            Some(case.expected_status),
            "generated x86 case {} returned the wrong status\nsource:\n{}",
            case.label,
            case.source
        );
    }
}

#[test]
fn generated_x86_long_single_function_crosses_virtual_liveness_rows() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_7675_7365);
    let (source, expected_stdout) = generated_virtual_liveness_boundary_program(&mut rng);
    let source_for_compile = source.clone();
    let bytes = common::run_gpu_codegen_with_timeout(
        &format!("GPU x86 virtual liveness boundary\nsource:\n{source}"),
        move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
                &source_for_compile,
            ))
        },
    )
    .unwrap_or_else(|err| {
        panic!("virtual liveness boundary program should compile\nsource:\n{source}\nerror: {err}")
    });

    let output = common::run_x86_64_elf_output(
        "virtual liveness boundary program",
        "virtual_liveness_boundary",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(String::from_utf8_lossy(&output.stdout), expected_stdout);
}

#[test]
fn generated_x86_u32_local_comparisons_are_name_independent() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_7533_3263);

    for case_i in 0..6 {
        let [left_local, right_local] = random_distinct_idents::<2>(&mut rng);
        let left = if case_i % 2 == 0 {
            u32::MAX - rng.random_range(0..=8)
        } else {
            rng.random_range(0..=64)
        };
        let right = if case_i % 2 == 0 {
            rng.random_range(1..=64)
        } else {
            u32::MAX - rng.random_range(0..=8)
        };
        let (op, condition) = generated_u32_compare(&mut rng, left, right);
        let then_value = rng.random_range(1..=63);
        let else_value = rng.random_range(64..=120);
        let expected = if condition { then_value } else { else_value };
        let source = format!(
            "fn main() {{\n    let {left_local}: u32 = {left};\n    let {right_local}: u32 = {right};\n    if ({left_local} {op} {right_local}) {{\n        return {then_value};\n    }} else {{\n        return {else_value};\n    }}\n}}\n"
        );

        let source_for_compile = source.clone();
        let bytes = common::run_gpu_codegen_with_timeout(
            &format!("GPU x86 u32 local comparison property {case_i}\nsource:\n{source}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source_for_compile)),
        )
        .unwrap_or_else(|err| {
            panic!("u32 local comparison property {case_i} should compile\nsource:\n{source}\nerror: {err}")
        });

        let output = common::run_x86_64_elf_output(
            format!("u32 local comparison property {case_i}"),
            &format!("u32_local_comparison_{case_i}"),
            &bytes,
        );
        assert_eq!(
            output.status.code(),
            Some(expected),
            "u32 local comparison property {case_i} returned the wrong status\nsource:\n{source}"
        );
    }
}

#[test]
fn generated_x86_u32_nested_comparisons_use_projected_expression_types() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_7533_326e);

    for case_i in 0..4 {
        let [left_local, right_local] = random_distinct_idents::<2>(&mut rng);
        let depth = 12 + case_i;
        let mut left_expr = left_local.clone();
        for _ in 0..depth {
            left_expr = format!("({left_expr} + 0)");
        }
        let then_value = rng.random_range(1..=63);
        let else_value = rng.random_range(64..=120);
        let source = format!(
            "fn main() {{\n    let {left_local}: u32 = 4294967295;\n    let {right_local}: u32 = 1;\n    if ({left_expr} > {right_local}) {{\n        return {then_value};\n    }} else {{\n        return {else_value};\n    }}\n}}\n"
        );

        let source_for_compile = source.clone();
        let bytes = common::run_gpu_codegen_with_timeout(
            &format!("GPU x86 u32 nested comparison property {case_i}\nsource:\n{source}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source_for_compile)),
        )
        .unwrap_or_else(|err| {
            panic!("u32 nested comparison property {case_i} should compile\nsource:\n{source}\nerror: {err}")
        });

        let output = common::run_x86_64_elf_output(
            format!("u32 nested comparison property {case_i}"),
            &format!("u32_nested_comparison_{case_i}"),
            &bytes,
        );
        assert_eq!(
            output.status.code(),
            Some(then_value),
            "u32 nested comparison property {case_i} returned the wrong status\nsource:\n{source}"
        );
    }
}

#[test]
fn generated_x86_prints_nested_call_results_from_hir_arguments() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_7072_696e);

    for case_i in 0..4 {
        let [add_fn, double_fn, left_param, right_param, double_param] =
            random_distinct_idents::<5>(&mut rng);
        let value = rng.random_range(1..=32);
        let expected = value * 2;
        let source = format!(
            "fn {add_fn}({left_param}: i32, {right_param}: i32) -> i32 {{\n    return {left_param} + {right_param};\n}}\nfn {double_fn}({double_param}: i32) -> i32 {{\n    return {add_fn}({double_param}, {double_param});\n}}\nfn main() {{\n    print({double_fn}({}));\n    return 0;\n}}\n",
            i32_lit(value)
        );

        let bytes = common::run_gpu_codegen_with_timeout(
            &format!("GPU x86 nested-call print property {case_i}\nsource:\n{source}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .unwrap_or_else(|err| panic!("nested-call print property {case_i} should compile: {err}"));

        let output = common::run_x86_64_elf_output(
            format!("nested-call print property {case_i}"),
            &format!("nested_call_print_{case_i}"),
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            format!("{expected}\n")
        );
    }
}

#[test]
fn generated_x86_array_return_abi_is_name_independent() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_6167_6772);

    for case_i in 0..2 {
        let [
            copy_fn,
            fill_fn,
            reverse_fn,
            pair_fn,
            sum_fn,
            copy_param,
            fill_param,
            reverse_param,
            pair_left,
            pair_right,
            sum_param,
            values_local,
            copied_local,
            reversed_local,
            filled_local,
            pair_local,
        ] = random_distinct_idents::<16>(&mut rng);
        let values = [
            rng.random_range(1..=9),
            rng.random_range(1..=9),
            rng.random_range(1..=9),
            rng.random_range(1..=9),
        ];
        let expected = 5 * values[3] + values[0];
        let source = format!(
            "fn {copy_fn}({copy_param}: [i32; 4]) -> [i32; 4] {{\n    return {copy_param};\n}}\n\
             fn {fill_fn}({fill_param}: i32) -> [i32; 4] {{\n    return [{fill_param}, {fill_param}, {fill_param}, {fill_param}];\n}}\n\
             fn {reverse_fn}({reverse_param}: [i32; 4]) -> [i32; 4] {{\n    return [{reverse_param}[3], {reverse_param}[2], {reverse_param}[1], {reverse_param}[0]];\n}}\n\
             fn {pair_fn}({pair_left}: i32, {pair_right}: i32) -> [i32; 2] {{\n    return [{pair_left}, {pair_right}];\n}}\n\
             fn {sum_fn}({sum_param}: [i32; 4]) -> i32 {{\n    return {sum_param}[0] + {sum_param}[1] + {sum_param}[2] + {sum_param}[3];\n}}\n\
             fn main() {{\n    let {values_local}: [i32; 4] = [{}, {}, {}, {}];\n    let {copied_local}: [i32; 4] = {copy_fn}({values_local});\n    let {reversed_local}: [i32; 4] = {reverse_fn}({copied_local});\n    let {filled_local}: [i32; 4] = {fill_fn}({reversed_local}[0]);\n    let {pair_local}: [i32; 2] = {pair_fn}({filled_local}[1], {reversed_local}[3]);\n    print({sum_fn}({filled_local}) + {pair_local}[0] + {pair_local}[1]);\n    return 0;\n}}\n",
            i32_lit(values[0]),
            i32_lit(values[1]),
            i32_lit(values[2]),
            i32_lit(values[3]),
        );

        let source_for_compile = source.clone();
        let bytes = common::run_gpu_codegen_with_timeout(
            &format!("GPU x86 aggregate array ABI property {case_i}\nsource:\n{source}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source_for_compile)),
        )
        .unwrap_or_else(|err| {
            panic!(
                "aggregate array ABI property {case_i} should compile\nsource:\n{source}\nerror: {err}"
            )
        });

        let output = common::run_x86_64_elf_output(
            format!("aggregate array ABI property {case_i}"),
            &format!("aggregate_array_abi_{case_i}"),
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            format!("{expected}\n")
        );
    }
}

#[test]
fn generated_x86_unit_enum_match_is_name_independent() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_656e_756d);
    let [enum_name, left_variant, right_variant, value_local] =
        random_distinct_idents::<4>(&mut rng);
    let expected = rng.random_range(3..=9);
    let fallback = rng.random_range(10..=19);
    let source = format!(
        "enum {enum_name} {{\n    {left_variant},\n    {right_variant},\n}}\n\
         fn main() {{\n    let {value_local}: {enum_name} = {right_variant};\n    return match ({value_local}) {{\n        {left_variant} -> {},\n        {right_variant} -> {},\n    }};\n}}\n",
        i32_lit(fallback),
        i32_lit(expected),
    );

    let bytes = common::run_gpu_codegen_with_timeout(
        &format!("GPU x86 unit enum match property\nsource:\n{source}"),
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .unwrap_or_else(|err| panic!("unit enum match property should compile: {err}"));

    let output =
        common::run_x86_64_elf_output("unit enum match property", "unit_enum_match", &bytes);
    assert_eq!(output.status.code(), Some(expected));
}

#[test]
fn generated_x86_return_match_allows_call_commas_in_arm_results() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_6d61_7463);
    let [
        enum_name,
        left_variant,
        right_variant,
        add_fn,
        value_local,
        seed_local,
        a_param,
        b_param,
        c_param,
        d_param,
    ] = random_distinct_idents::<10>(&mut rng);
    let args = [
        rng.random_range(1..=8),
        rng.random_range(1..=8),
        rng.random_range(1..=8),
        rng.random_range(1..=8),
    ];
    let seed = rng.random_range(1..=16);
    let expected = args.iter().sum::<i32>() + seed;
    let source = format!(
        "enum {enum_name} {{\n    {left_variant},\n    {right_variant},\n}}\n\
         fn {add_fn}({a_param}: i32, {b_param}: i32, {c_param}: i32, {d_param}: i32) -> i32 {{\n    return {a_param} + {b_param} + {c_param} + {d_param};\n}}\n\
         fn main() {{\n    let {value_local}: {enum_name} = {left_variant};\n    let {seed_local}: i32 = {};\n    return match ({value_local}) {{\n        {left_variant} -> ({add_fn}({}, {}, {}, {})) + {seed_local},\n        {right_variant} -> {seed_local} * 2,\n    }};\n}}\n",
        i32_lit(seed),
        i32_lit(args[0]),
        i32_lit(args[1]),
        i32_lit(args[2]),
        i32_lit(args[3]),
    );

    let bytes = common::run_gpu_codegen_with_timeout(
        &format!("GPU x86 return-match call-comma property\nsource:\n{source}"),
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .unwrap_or_else(|err| panic!("return-match call-comma property should compile: {err}"));

    let output = common::run_x86_64_elf_output(
        "return-match call-comma property",
        "return_match_call_commas",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(exit_status(expected)));
}

#[test]
fn generated_x86_struct_copy_member_assignment_and_abi_are_name_independent() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_7374_7275);

    for case_i in 0..4 {
        let [
            struct_name,
            first_field,
            second_field,
            make_fn,
            bump_fn,
            score_fn,
            make_left,
            make_right,
            pair_param,
            amount_param,
            score_param,
            pair_local,
            next_local,
            copied_local,
        ] = random_distinct_idents::<14>(&mut rng);
        let left = rng.random_range(1..=12);
        let right = rng.random_range(1..=12);
        let amount = rng.random_range(1..=7);
        let bumped_first = left + amount;
        let expected = bumped_first * 10 + (bumped_first - 1);
        let source = format!(
            "struct {struct_name} {{\n    {first_field}: i32,\n    {second_field}: i32,\n}}\n\
             fn {make_fn}({make_left}: i32, {make_right}: i32) -> {struct_name} {{\n    return {struct_name} {{ {first_field}: {make_left}, {second_field}: {make_right} }};\n}}\n\
             fn {bump_fn}({pair_param}: {struct_name}, {amount_param}: i32) -> {struct_name} {{\n    let {next_local}: {struct_name} = {pair_param};\n    {next_local}.{first_field} += {amount_param};\n    {next_local}.{second_field} = {next_local}.{first_field} - 1;\n    return {next_local};\n}}\n\
             fn {score_fn}({score_param}: {struct_name}) -> i32 {{\n    return {score_param}.{first_field} * 10 + {score_param}.{second_field};\n}}\n\
             fn main() {{\n    let {pair_local}: {struct_name} = {make_fn}({}, {});\n    let {copied_local}: {struct_name} = {bump_fn}({pair_local}, {});\n    print({score_fn}({copied_local}));\n    return 0;\n}}\n",
            i32_lit(left),
            i32_lit(right),
            i32_lit(amount),
        );

        let bytes = common::run_gpu_codegen_with_timeout(
            &format!("GPU x86 aggregate struct ABI property {case_i}\nsource:\n{source}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .unwrap_or_else(|err| {
            panic!("aggregate struct ABI property {case_i} should compile: {err}")
        });

        let output = common::run_x86_64_elf_output(
            format!("aggregate struct ABI property {case_i}"),
            &format!("aggregate_struct_abi_{case_i}"),
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            format!("{expected}\n")
        );
    }
}

#[test]
fn generated_x86_recursive_calls_compose_with_enclosing_expressions() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_7265_6375);

    for case_i in 0..3 {
        let [factorial_fn, input_param] = random_distinct_idents::<2>(&mut rng);
        let input = rng.random_range(3..=6);
        let expected = factorial(input);
        let source = format!(
            "fn {factorial_fn}({input_param}: i32) -> i32 {{\n    if ({input_param} <= 1) {{\n        return 1;\n    }} else {{\n        return {input_param} * {factorial_fn}({input_param} - 1);\n    }}\n}}\nfn main() {{\n    print({factorial_fn}({}));\n    return 0;\n}}\n",
            i32_lit(input)
        );

        let bytes = common::run_gpu_codegen_with_timeout(
            &format!("GPU x86 recursive call property {case_i}\nsource:\n{source}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .unwrap_or_else(|err| panic!("recursive call property {case_i} should compile: {err}"));

        let output = common::run_x86_64_elf_output(
            format!("recursive call property {case_i}"),
            &format!("recursive_call_{case_i}"),
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            format!("{expected}\n")
        );
    }
}

#[test]
fn generated_x86_compound_assignments_preserve_call_results() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_6361_7373);

    for case_i in 0..4 {
        let [
            helper_fn,
            left_param,
            right_param,
            total_local,
            left_local,
            right_local,
        ] = random_distinct_idents::<6>(&mut rng);
        let seed = rng.random_range(1..=12);
        let left = rng.random_range(2..=9);
        let right = rng.random_range(3..=11);
        let extra = rng.random_range(1..=7);
        let first = left * 2 + right;
        let second = right * 2 + extra;
        let expected = seed + first + second;
        let source = format!(
            "fn {helper_fn}({left_param}: i32, {right_param}: i32) -> i32 {{\n    return ({left_param} * 2) + {right_param};\n}}\n\
             fn main() {{\n    let {total_local}: i32 = {};\n    let {left_local}: i32 = {};\n    let {right_local}: i32 = {};\n    {total_local} += {helper_fn}({left_local}, {right_local});\n    {total_local} += {helper_fn}({right_local}, {});\n    print({total_local});\n    return 0;\n}}\n",
            i32_lit(seed),
            i32_lit(left),
            i32_lit(right),
            i32_lit(extra)
        );

        let bytes = common::run_gpu_codegen_with_timeout(
            &format!("GPU x86 compound assignment call property {case_i}\nsource:\n{source}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .unwrap_or_else(|err| {
            panic!("compound assignment call property {case_i} should compile: {err}")
        });

        let output = common::run_x86_64_elf_output(
            format!("compound assignment call property {case_i}"),
            &format!("compound_assignment_call_{case_i}"),
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            format!("{expected}\n")
        );
    }
}

#[test]
fn generated_x86_array_for_loop_is_name_independent() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_666f_7261);
    let [values_name, value_name, total_name] = random_distinct_idents::<3>(&mut rng);
    let values = [
        rng.random_range(1..=9),
        rng.random_range(1..=9),
        rng.random_range(1..=9),
        rng.random_range(1..=9),
    ];
    let expected: i32 = values.iter().sum();
    let source = format!(
        "fn main() {{\n    let {values_name}: [i32; 4] = [{}, {}, {}, {}];\n    let {total_name}: i32 = 0;\n    for {value_name} in {values_name} {{\n        {total_name} += {value_name};\n    }}\n    print({total_name});\n    return 0;\n}}\n",
        i32_lit(values[0]),
        i32_lit(values[1]),
        i32_lit(values[2]),
        i32_lit(values[3]),
    );

    let bytes = common::run_gpu_codegen_with_timeout(
        &format!("GPU x86 array-for property\nsource:\n{source}"),
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .unwrap_or_else(|err| panic!("array-for property should compile: {err}"));

    let output = common::run_x86_64_elf_output("array-for property", "array_for_property", &bytes);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(
        String::from_utf8_lossy(&output.stdout),
        format!("{expected}\n")
    );
}

#[test]
fn generated_x86_interval_for_loop_is_name_independent() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_666f_7269);

    for case_i in 0..4 {
        let [
            interval_type,
            lower_field,
            upper_field,
            make_fn,
            make_lower,
            make_upper,
            interval_local,
            item_local,
            total_local,
        ] = random_distinct_idents::<9>(&mut rng);
        let lower = rng.random_range(0..=6);
        let upper = lower + rng.random_range(1..=6);
        let iter_sum: i32 = (lower..upper).sum();
        let expected = iter_sum + lower + upper;
        let source = format!(
            "struct {interval_type} {{\n    {lower_field}: i32,\n    {upper_field}: i32,\n}}\n\
             fn {make_fn}({make_lower}: i32, {make_upper}: i32) -> {interval_type} {{\n    return {interval_type} {{ {lower_field}: {make_lower}, {upper_field}: {make_upper} }};\n}}\n\
             fn main() {{\n    let {interval_local}: {interval_type} = {make_fn}({}, {});\n    let {total_local}: i32 = 0;\n    for {item_local} in {interval_local} {{\n        {total_local} += {item_local};\n    }}\n    print({total_local} + {interval_local}.{lower_field} + {interval_local}.{upper_field});\n    return 0;\n}}\n",
            i32_lit(lower),
            i32_lit(upper),
        );

        let bytes = common::run_gpu_codegen_with_timeout(
            &format!("GPU x86 interval-for property {case_i}\nsource:\n{source}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .unwrap_or_else(|err| panic!("interval-for property {case_i} should compile: {err}"));

        let output = common::run_x86_64_elf_output(
            format!("interval-for property {case_i}"),
            &format!("interval_for_property_{case_i}"),
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            format!("{expected}\n")
        );
    }
}

#[test]
fn generated_x86_slice_param_indexing_is_name_independent() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_736c_6963);

    for case_i in 0..4 {
        let [pick_fn, values_param, index_param, values_local] =
            random_distinct_idents::<4>(&mut rng);
        let values = [
            rng.random_range(1..=9),
            rng.random_range(1..=9),
            rng.random_range(1..=9),
            rng.random_range(1..=9),
        ];
        let index = rng.random_range(0..4);
        let expected = values[index];
        let source = format!(
            "fn {pick_fn}({values_param}: [i32], {index_param}: i32) -> i32 {{\n    return {values_param}[{index_param}];\n}}\n\
             fn main() {{\n    let {values_local}: [i32; 4] = [{}, {}, {}, {}];\n    print({pick_fn}({values_local}, {}));\n    return 0;\n}}\n",
            i32_lit(values[0]),
            i32_lit(values[1]),
            i32_lit(values[2]),
            i32_lit(values[3]),
            i32_lit(index as i32),
        );

        let bytes = common::run_gpu_codegen_with_timeout(
            &format!("GPU x86 slice-param index property {case_i}\nsource:\n{source}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .unwrap_or_else(|err| panic!("slice-param index property {case_i} should compile: {err}"));

        let output = common::run_x86_64_elf_output(
            format!("slice-param index property {case_i}"),
            &format!("slice_param_index_{case_i}"),
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            format!("{expected}\n")
        );
    }
}

#[test]
fn generated_x86_mixed_four_arg_calls_preserve_argument_values() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_3461_7267);

    for case_i in 0..4 {
        let [
            get_fn,
            values_param,
            len_param,
            index_param,
            fallback_param,
            values_local,
            hit_local,
            miss_local,
        ] = random_distinct_idents::<8>(&mut rng);
        let values = [
            rng.random_range(1..=9),
            rng.random_range(1..=9),
            rng.random_range(1..=9),
            rng.random_range(1..=9),
        ];
        let hit_index = rng.random_range(0..4);
        let miss_index = rng.random_range(5..=11);
        let fallback = rng.random_range(10..=30);
        let expected = values[hit_index] + fallback;
        let source = format!(
            "fn {get_fn}({values_param}: [i32], {len_param}: i32, {index_param}: i32, {fallback_param}: i32) -> i32 {{\n    if ({index_param} >= {len_param}) {{\n        return {fallback_param};\n    }} else {{\n        return {values_param}[{index_param}];\n    }}\n}}\n\
             fn main() {{\n    let {values_local}: [i32; 4] = [{}, {}, {}, {}];\n    let {hit_local}: i32 = {get_fn}({values_local}, 4, {}, 0);\n    let {miss_local}: i32 = {get_fn}({values_local}, 4, {}, {});\n    print({hit_local} + {miss_local});\n    return 0;\n}}\n",
            i32_lit(values[0]),
            i32_lit(values[1]),
            i32_lit(values[2]),
            i32_lit(values[3]),
            i32_lit(hit_index as i32),
            i32_lit(miss_index),
            i32_lit(fallback),
        );

        let bytes = common::run_gpu_codegen_with_timeout(
            &format!("GPU x86 mixed four-arg call property {case_i}\nsource:\n{source}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .unwrap_or_else(|err| {
            panic!("mixed four-arg call property {case_i} should compile: {err}")
        });

        let output = common::run_x86_64_elf_output(
            format!("mixed four-arg call property {case_i}"),
            &format!("mixed_four_arg_call_{case_i}"),
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            format!("{expected}\n")
        );
    }
}

#[test]
fn generated_x86_scalar_three_and_four_arg_calls_preserve_argument_values() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_7363_616c);

    for case_i in 0..4 {
        let [
            tri_fn,
            quad_fn,
            a_param,
            b_param,
            c_param,
            d_param,
            tri_local,
            quad_local,
        ] = random_distinct_idents::<8>(&mut rng);
        let values = [
            rng.random_range(1..=9),
            rng.random_range(1..=9),
            rng.random_range(1..=9),
            rng.random_range(1..=9),
        ];
        let tri_expected = values[0] + values[1] * values[2];
        let quad_expected = values[0] * values[1] + values[2] - values[3];
        let expected = tri_expected + quad_expected;
        let source = format!(
            "fn {tri_fn}({a_param}: i32, {b_param}: i32, {c_param}: i32) -> i32 {{\n    return {a_param} + {b_param} * {c_param};\n}}\n\
             fn {quad_fn}({a_param}: i32, {b_param}: i32, {c_param}: i32, {d_param}: i32) -> i32 {{\n    return {a_param} * {b_param} + {c_param} - {d_param};\n}}\n\
             fn main() {{\n    let {tri_local}: i32 = {tri_fn}({}, {}, {});\n    let {quad_local}: i32 = {quad_fn}({}, {}, {}, {});\n    print({tri_local} + {quad_local});\n    return 0;\n}}\n",
            i32_lit(values[0]),
            i32_lit(values[1]),
            i32_lit(values[2]),
            i32_lit(values[0]),
            i32_lit(values[1]),
            i32_lit(values[2]),
            i32_lit(values[3]),
        );

        let bytes = common::run_gpu_codegen_with_timeout(
            &format!("GPU x86 scalar 3/4-arg call property {case_i}\nsource:\n{source}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .unwrap_or_else(|err| {
            panic!("scalar 3/4-arg call property {case_i} should compile: {err}")
        });

        let output = common::run_x86_64_elf_output(
            format!("scalar 3/4-arg call property {case_i}"),
            &format!("scalar_three_four_arg_call_{case_i}"),
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            format!("{expected}\n")
        );
    }
}

fn generated_program(rng: &mut StdRng, case_i: usize) -> GeneratedProgram {
    match rng.random_range(0..6) {
        0 => {
            let value = rng.random_range(-32..=32);
            GeneratedProgram {
                label: format!("literal_{case_i}"),
                source: format!("fn main() {{\n    return {};\n}}\n", i32_lit(value)),
                expected_status: exit_status(value),
            }
        }
        1 => {
            let local = random_ident(rng);
            let value = rng.random_range(-32..=32);
            GeneratedProgram {
                label: format!("local_{case_i}_{local}"),
                source: format!(
                    "fn main() {{\n    let {local}: i32 = {};\n    return {local};\n}}\n",
                    i32_lit(value)
                ),
                expected_status: exit_status(value),
            }
        }
        2 => {
            let left = rng.random_range(0..=24);
            let right = rng.random_range(1..=24);
            let (op_source, value) = generated_i32_binary(rng, left, right);
            GeneratedProgram {
                label: format!("binary_{case_i}"),
                source: format!(
                    "fn main() {{\n    return {} {op_source} {};\n}}\n",
                    i32_lit(left),
                    i32_lit(right)
                ),
                expected_status: exit_status(value),
            }
        }
        3 => {
            let local = random_ident(rng);
            let left = rng.random_range(-16..=16);
            let right = rng.random_range(1..=24);
            let (op_source, value) = generated_i32_binary(rng, left, right);
            GeneratedProgram {
                label: format!("local_binary_{case_i}_{local}"),
                source: format!(
                    "fn main() {{\n    let {local}: i32 = {};\n    return {local} {op_source} {};\n}}\n",
                    i32_lit(left),
                    i32_lit(right)
                ),
                expected_status: exit_status(value),
            }
        }
        4 => {
            let left_name = random_ident(rng);
            let right_name = random_ident(rng);
            let left = rng.random_bool(0.5);
            let right = rng.random_bool(0.5);
            let use_and = rng.random_bool(0.5);
            let value = if use_and {
                left && right
            } else {
                left || right
            };
            GeneratedProgram {
                label: format!("bool_binary_{case_i}_{left_name}_{right_name}"),
                source: format!(
                    "fn main() -> bool {{\n    let {left_name}: bool = {};\n    let {right_name}: bool = {};\n    return {left_name} {} {right_name};\n}}\n",
                    bool_lit(left),
                    bool_lit(right),
                    if use_and { "&&" } else { "||" }
                ),
                expected_status: if value { 1 } else { 0 },
            }
        }
        _ => {
            let local = random_ident(rng);
            let left = rng.random_range(-16..=16);
            let right = rng.random_range(0..=16);
            let then_value = rng.random_range(-32..=32);
            let else_value = rng.random_range(-32..=32);
            let (cmp_source, condition) = generated_compare(rng, left, right);
            let value = if condition { then_value } else { else_value };
            GeneratedProgram {
                label: format!("terminal_if_{case_i}_{local}"),
                source: format!(
                    "fn main() {{\n    let {local}: i32 = {};\n    if ({local} {cmp_source} {}) {{ return {}; }} else {{ return {}; }}\n}}\n",
                    i32_lit(left),
                    i32_lit(right),
                    i32_lit(then_value),
                    i32_lit(else_value)
                ),
                expected_status: exit_status(value),
            }
        }
    }
}

fn generated_i32_binary(rng: &mut StdRng, left: i32, right: i32) -> (&'static str, i32) {
    let shift = (right as u32) & 31;
    match rng.random_range(0..10) {
        0 => ("+", left.wrapping_add(right)),
        1 => ("-", left.wrapping_sub(right)),
        2 => ("*", left.wrapping_mul(right)),
        3 => ("/", left / right),
        4 => ("%", left % right),
        5 => ("&", left & right),
        6 => ("|", left | right),
        7 => ("^", left ^ right),
        8 => ("<<", left.wrapping_shl(shift)),
        _ => (">>", left >> shift),
    }
}

fn generated_mod_program(rng: &mut StdRng) -> GeneratedProgram {
    let local = random_ident(rng);
    let left = rng.random_range(-64..=64);
    let right = rng.random_range(1..=31);
    let value = left % right;
    GeneratedProgram {
        label: format!("mod_{local}"),
        source: format!(
            "fn main() {{\n    let {local}: i32 = {};\n    return {local} % {};\n}}\n",
            i32_lit(left),
            i32_lit(right)
        ),
        expected_status: exit_status(value),
    }
}

fn generated_extended_binary_programs(rng: &mut StdRng) -> Vec<GeneratedProgram> {
    [
        ("/", 27, 4, 27 / 4),
        ("&", 0b1101, 0b1011, 0b1101 & 0b1011),
        ("|", 0b0101, 0b1010, 0b0101 | 0b1010),
        ("^", 0b1110, 0b0110, 0b1110 ^ 0b0110),
        ("<<", 3, 2, 3i32.wrapping_shl(2)),
        (">>", -16, 2, -16 >> 2),
    ]
    .into_iter()
    .enumerate()
    .map(|(case_i, (op, left, right, value))| {
        let local = random_ident(rng);
        GeneratedProgram {
            label: format!("extended_binary_{case_i}_{local}"),
            source: format!(
                "fn main() {{\n    let {local}: i32 = {};\n    return {local} {op} {};\n}}\n",
                i32_lit(left),
                i32_lit(right)
            ),
            expected_status: exit_status(value),
        }
    })
    .collect()
}

fn generated_local_constant_chain_programs(rng: &mut StdRng) -> Vec<GeneratedProgram> {
    (0..4)
        .map(|case_i| {
            let [first_local, second_local] = random_distinct_idents::<2>(rng);
            let left = rng.random_range(0..=31);
            let right = rng.random_range(1..=15);
            let tail = rng.random_range(0..=31);
            let (op_source, first_value) = generated_i32_binary(rng, left, right);
            let final_value = first_value.wrapping_add(tail);
            GeneratedProgram {
                label: format!("local_chain_{case_i}_{first_local}_{second_local}"),
                source: format!(
                    "fn main() {{\n    let {first_local}: i32 = {} {op_source} {};\n    let {second_local}: i32 = {first_local} + {};\n    return {second_local};\n}}\n",
                    i32_lit(left),
                    i32_lit(right),
                    i32_lit(tail)
                ),
                expected_status: exit_status(final_value),
            }
        })
        .collect()
}

fn generated_call_programs(rng: &mut StdRng) -> Vec<GeneratedProgram> {
    let [callee, param, local] = random_distinct_idents::<3>(rng);
    let value = rng.random_range(-32..=32);
    let identity_local = GeneratedProgram {
        label: format!("call_identity_local_{callee}_{local}"),
        source: format!(
            "fn {callee}({param}: i32) -> i32 {{\n    return {param};\n}}\nfn main() {{\n    let {local}: i32 = {};\n    return {callee}({local});\n}}\n",
            i32_lit(value)
        ),
        expected_status: exit_status(value),
    };

    let [callee, left_param, right_param] = random_distinct_idents::<3>(rng);
    let left = rng.random_range(-16..=16);
    let right = rng.random_range(-16..=16);
    let add_literals = GeneratedProgram {
        label: format!("call_add_literals_{callee}"),
        source: format!(
            "fn {callee}({left_param}: i32, {right_param}: i32) -> i32 {{\n    return {left_param} + {right_param};\n}}\nfn main() {{\n    return {callee}({}, {});\n}}\n",
            i32_lit(left),
            i32_lit(right)
        ),
        expected_status: exit_status(left.wrapping_add(right)),
    };

    let [callee, left_param, right_param] = random_distinct_idents::<3>(rng);
    let a = rng.random_range(0..=8);
    let b = rng.random_range(0..=8);
    let c = rng.random_range(0..=8);
    let d = rng.random_range(0..=8);
    let binary_args = GeneratedProgram {
        label: format!("call_add_binary_args_{callee}"),
        source: format!(
            "fn {callee}({left_param}: i32, {right_param}: i32) -> i32 {{\n    return {left_param} + {right_param};\n}}\nfn main() {{\n    return {callee}({} * {}, {} - {});\n}}\n",
            i32_lit(a),
            i32_lit(b),
            i32_lit(c),
            i32_lit(d)
        ),
        expected_status: exit_status(a.wrapping_mul(b).wrapping_add(c.wrapping_sub(d))),
    };

    let [inner, outer, left_param, right_param, outer_param] = random_distinct_idents::<5>(rng);
    let nested_value = rng.random_range(-16..=16);
    let nested_call = GeneratedProgram {
        label: format!("call_nested_return_{outer}_{inner}"),
        source: format!(
            "fn {inner}({left_param}: i32, {right_param}: i32) -> i32 {{\n    return {left_param} + {right_param};\n}}\nfn {outer}({outer_param}: i32) -> i32 {{\n    return {inner}({outer_param}, {outer_param});\n}}\nfn main() {{\n    return {outer}({});\n}}\n",
            i32_lit(nested_value)
        ),
        expected_status: exit_status(nested_value.wrapping_add(nested_value)),
    };

    let [callee, first_local, second_local, param] = random_distinct_idents::<4>(rng);
    let first = rng.random_range(-16..=16);
    let second = rng.random_range(-16..=16);
    let call_let_chain = GeneratedProgram {
        label: format!("call_let_chain_{callee}_{first_local}_{second_local}"),
        source: format!(
            "fn {callee}({param}: i32) -> i32 {{\n    return {param};\n}}\nfn main() {{\n    let {first_local}: i32 = {callee}({});\n    let {second_local}: i32 = {callee}({});\n    return {first_local} + {second_local};\n}}\n",
            i32_lit(first),
            i32_lit(second)
        ),
        expected_status: exit_status(first.wrapping_add(second)),
    };

    let [callee, param] = random_distinct_idents::<2>(rng);
    let a: i32 = rng.random_range(0..=8);
    let b: i32 = rng.random_range(0..=8);
    let c: i32 = rng.random_range(0..=8);
    let d: i32 = rng.random_range(0..=8);
    let e: i32 = rng.random_range(0..=8);
    let nested_arg_value = (a + b).wrapping_mul(c.wrapping_sub(d)).wrapping_add(e);
    let nested_expr_arg = GeneratedProgram {
        label: format!("call_nested_expr_arg_{callee}"),
        source: format!(
            "fn {callee}({param}: i32) -> i32 {{\n    return {param};\n}}\nfn main() {{\n    return {callee}((({} + {}) * ({} - {})) + {});\n}}\n",
            i32_lit(a),
            i32_lit(b),
            i32_lit(c),
            i32_lit(d),
            i32_lit(e)
        ),
        expected_status: exit_status(nested_arg_value),
    };

    vec![
        identity_local,
        add_literals,
        binary_args,
        nested_call,
        call_let_chain,
        nested_expr_arg,
    ]
}

fn generated_mutable_loop_programs(rng: &mut StdRng) -> Vec<GeneratedProgram> {
    (0..4)
        .map(|case_i| {
            let [index, total, step_name] = random_distinct_idents::<3>(rng);
            let limit = rng.random_range(2..=9);
            let seed = rng.random_range(-8..=8);
            let step = rng.random_range(1..=5);
            let expected = seed + limit * step;
            GeneratedProgram {
                label: format!("mutable_loop_{case_i}_{index}_{total}_{step_name}"),
                source: format!(
                    "fn main() {{\n    let {index}: i32 = 0;\n    let {total}: i32 = {};\n    let {step_name}: i32 = {};\n    while ({index} < {}) {{\n        {total} += {step_name};\n        {index} += 1;\n    }}\n    return {total};\n}}\n",
                    i32_lit(seed),
                    i32_lit(step),
                    i32_lit(limit)
                ),
                expected_status: exit_status(expected),
            }
        })
        .collect()
}

fn generated_nested_dependency_programs(rng: &mut StdRng) -> Vec<GeneratedProgram> {
    (0..4)
        .map(|case_i| {
            let [base, shifted] = random_distinct_idents::<2>(rng);
            let a = rng.random_range(0..=31);
            let b = rng.random_range(0..=31);
            let c = rng.random_range(0..=31);
            let d = rng.random_range(0..=31);
            let left_shift = rng.random_range(1..=3);
            let right_shift = rng.random_range(1..=3);
            let base_value: i32 = (a & b) | (c ^ d);
            let expected = base_value.wrapping_shl(left_shift as u32) >> right_shift;
            GeneratedProgram {
                label: format!("nested_dependency_{case_i}_{base}_{shifted}"),
                source: format!(
                    "fn main() {{\n    let {base}: i32 = ({} & {}) | ({} ^ {});\n    let {shifted}: i32 = {base} << {} >> {};\n    return {shifted};\n}}\n",
                    i32_lit(a),
                    i32_lit(b),
                    i32_lit(c),
                    i32_lit(d),
                    i32_lit(left_shift),
                    i32_lit(right_shift)
                ),
                expected_status: exit_status(expected),
            }
        })
        .collect()
}

fn generated_bool_branch_program(rng: &mut StdRng) -> GeneratedProgram {
    let [flag, left_local, right_local] = random_distinct_idents::<3>(rng);
    GeneratedProgram {
        label: format!("bool_branch_live_compare_{flag}_{left_local}_{right_local}"),
        source: format!(
            "fn main() {{\n    let {flag}: bool = (3 < 4) && !(5 == 6);\n    let {left_local}: i32 = 1;\n    let {right_local}: i32 = 2;\n    if ({flag} || ({left_local} > {right_local})) {{ return 7; }} else {{ return 9; }}\n}}\n"
        ),
        expected_status: 7,
    }
}

fn generated_loop_control_program(rng: &mut StdRng) -> GeneratedProgram {
    let [index, total] = random_distinct_idents::<2>(rng);
    let limit = rng.random_range(8..=12);
    let skip = rng.random_range(2..=4);
    let stop = rng.random_range(6..=limit);
    let expected = (1..stop).filter(|value| *value != skip).sum::<i32>();
    GeneratedProgram {
        label: format!("loop_control_{index}_{total}"),
        source: format!(
            "fn main() {{\n    let {index}: i32 = 0;\n    let {total}: i32 = 0;\n    while ({index} < {}) {{\n        {index} += 1;\n        if ({index} == {}) {{\n            continue;\n        }}\n        if ({index} == {}) {{\n            break;\n        }}\n        {total} += {index};\n    }}\n    return {total};\n}}\n",
            i32_lit(limit),
            i32_lit(skip),
            i32_lit(stop)
        ),
        expected_status: exit_status(expected),
    }
}

#[test]
fn generated_x86_precedence_expressions_print_expected_values() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_7072_6563);

    for case_i in 0..4 {
        let [first_local, second_local] = random_distinct_idents::<2>(&mut rng);
        let left = rng.random_range(1..=9);
        let middle = rng.random_range(1..=9);
        let right = rng.random_range(1..=9);
        let expected_first = left + middle * right;
        let expected_second = (left + middle) * right;
        let source = format!(
            "fn main() {{\n    let {first_local}: i32 = {} + {} * {};\n    let {second_local}: i32 = ({} + {}) * {};\n    print({first_local});\n    print({second_local});\n    return 0;\n}}\n",
            i32_lit(left),
            i32_lit(middle),
            i32_lit(right),
            i32_lit(left),
            i32_lit(middle),
            i32_lit(right),
        );

        let bytes = common::run_gpu_codegen_with_timeout(
            &format!("GPU x86 precedence property {case_i}\nsource:\n{source}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .unwrap_or_else(|err| panic!("precedence property {case_i} should compile: {err}"));

        let output = common::run_x86_64_elf_output(
            format!("precedence property {case_i}"),
            &format!("precedence_property_{case_i}"),
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            format!("{expected_first}\n{expected_second}\n")
        );
    }
}

#[test]
fn generated_x86_left_associative_tail_expressions_print_expected_values() {
    let mut rng = StdRng::seed_from_u64(0x7867_7075_7461_696c);

    for case_i in 0..3 {
        let [first_local, second_local] = random_distinct_idents::<2>(&mut rng);
        let a = rng.random_range(2..=9);
        let b = rng.random_range(2..=9);
        let c = rng.random_range(2..=9);
        let d = rng.random_range(1..=6);
        let e = rng.random_range(1..=6);
        let expected_first = a * b + c - d;
        let expected_second = a + b * c - d + e;
        let source = format!(
            "fn main() {{\n    let {first_local}: i32 = {} * {} + {} - {};\n    let {second_local}: i32 = {} + {} * {} - {} + {};\n    print({first_local});\n    print({second_local});\n    return 0;\n}}\n",
            i32_lit(a),
            i32_lit(b),
            i32_lit(c),
            i32_lit(d),
            i32_lit(a),
            i32_lit(b),
            i32_lit(c),
            i32_lit(d),
            i32_lit(e),
        );

        let bytes = common::run_gpu_codegen_with_timeout(
            &format!("GPU x86 left-associative tail property {case_i}\nsource:\n{source}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .unwrap_or_else(|err| {
            panic!("left-associative tail property {case_i} should compile: {err}")
        });

        let output = common::run_x86_64_elf_output(
            format!("left-associative tail property {case_i}"),
            &format!("left_assoc_tail_property_{case_i}"),
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            format!("{expected_first}\n{expected_second}\n")
        );
    }
}

fn generated_compare(rng: &mut StdRng, left: i32, right: i32) -> (&'static str, bool) {
    match rng.random_range(0..6) {
        0 => ("<", left < right),
        1 => (">", left > right),
        2 => ("<=", left <= right),
        3 => (">=", left >= right),
        4 => ("==", left == right),
        _ => ("!=", left != right),
    }
}

fn generated_u32_compare(rng: &mut StdRng, left: u32, right: u32) -> (&'static str, bool) {
    match rng.random_range(0..4) {
        0 => ("<", left < right),
        1 => (">", left > right),
        2 => ("<=", left <= right),
        _ => (">=", left >= right),
    }
}

fn i32_lit(value: i32) -> String {
    value.to_string()
}

fn bool_lit(value: bool) -> &'static str {
    if value { "true" } else { "false" }
}

fn generated_virtual_liveness_boundary_program(rng: &mut StdRng) -> (String, String) {
    const CHUNKS: [(
        i32,
        i32,
        i32,
        i32,
        i32,
        i32,
        i32,
        i32,
        i32,
        i32,
        i32,
        i32,
        i32,
    ); 4] = [
        (20, 14, 8, 1, 2, 11, 11, 6, 5, 9, 17, 3, 6),
        (10, 15, 4, 5, 8, 4, 5, 3, 8, 1, 21, 5, 6),
        (29, 7, 0, 0, 14, 12, 5, 15, 3, 0, 19, 4, 5),
        (22, 14, 8, 4, 20, 12, 1, 5, 4, 2, 13, 2, 7),
    ];
    let names = random_distinct_idents::<44>(rng);
    let pair_ty = &names[0];
    let field_a = &names[1];
    let field_b = &names[2];
    let helper = &names[3];
    let helper_param = &names[4];
    let acc = &names[5];
    let mut source = format!(
        "struct {pair_ty} {{\n    {field_a}: i32,\n    {field_b}: i32,\n}}\n\
         fn {helper}({helper_param}: i32) -> i32 {{\n    return {helper_param} + 1;\n}}\n\
         fn main() {{\n    let {acc}: i32 = 0;\n"
    );
    let mut expected_stdout = String::new();
    let mut value = 0i32;

    for (chunk_i, chunk) in CHUNKS.iter().enumerate() {
        let base = 6 + chunk_i * 9;
        let call_local = &names[base];
        let array_local = &names[base + 1];
        let iter_local = &names[base + 2];
        let struct_local = &names[base + 3];
        let index_local = &names[base + 4];
        let scratch_a = &names[base + 5];
        let scratch_b = &names[base + 6];
        let scratch_c = &names[base + 7];
        let scratch_d = &names[base + 8];
        let (
            add_base,
            mul_left,
            mul_right,
            tail,
            threshold,
            then_delta,
            else_delta,
            array_b,
            array_c,
            array_d,
            field_value,
            loop_delta,
            print_delta,
        ) = *chunk;

        let helper_arg = ((value + add_base) * (mul_left - mul_right)) + tail;
        let call_value = helper_arg + 1;
        value += call_value;
        if (value & 1) == 0 || value < threshold {
            value += then_delta;
        } else {
            value -= else_delta;
        }
        let array_values = [value, array_b, array_c, array_d];
        for item in array_values {
            value += item;
        }
        value += value + field_value;
        for _ in 0..2 {
            value += loop_delta;
        }
        expected_stdout.push_str(&format!("{}\n", value + print_delta));

        source.push_str(&format!(
            "    let {call_local}: i32 = {helper}((({acc} + {add_base}) * ({mul_left} - {mul_right})) + {tail});\n\
                 {acc} += {call_local};\n\
                 if (({acc} & 1) == 0 || {acc} < {threshold}) {{\n\
                     {acc} += {then_delta};\n\
                 }} else {{\n\
                     {acc} -= {else_delta};\n\
                 }}\n\
                 let {array_local}: [i32; 4] = [{acc}, {array_b}, {array_c}, {array_d}];\n\
                 for {iter_local} in {array_local} {{\n\
                     {acc} += {iter_local};\n\
                 }}\n\
                 let {struct_local}: {pair_ty} = {pair_ty} {{ {field_a}: {acc}, {field_b}: {field_value} }};\n\
                 {acc} += {struct_local}.{field_a} + {struct_local}.{field_b};\n\
                 let {index_local}: i32 = 0;\n\
                 while ({index_local} < 2) {{\n\
                     {acc} += {loop_delta};\n\
                     {index_local} += 1;\n\
                 }}\n\
                 let {scratch_a}: i32 = {acc} + {print_delta};\n\
                 let {scratch_b}: i32 = {scratch_a} + 0;\n\
                 let {scratch_c}: i32 = {scratch_b} - 0;\n\
                 let {scratch_d}: i32 = {scratch_c} + 0;\n\
                 print({scratch_d});\n"
        ));
    }
    source.push_str("    return 0;\n}\n");
    (source, expected_stdout)
}

fn exit_status(value: i32) -> i32 {
    (value as u32 & 0xff) as i32
}

fn factorial(value: i32) -> i32 {
    (1..=value).product()
}

fn random_ident(rng: &mut StdRng) -> String {
    const FIRST: &[u8] = b"abcdefghijklmnopqrstuvwxyz";
    const REST: &[u8] = b"abcdefghijklmnopqrstuvwxyz0123456789_";
    const KEYWORDS: &[&str] = &[
        "fn", "main", "let", "const", "return", "true", "false", "if", "else", "while", "break",
        "continue", "for", "in", "struct", "match", "i32", "u32", "u8", "bool", "print",
    ];

    loop {
        let len = rng.random_range(3..=10);
        let mut ident = String::with_capacity(len);
        ident.push(FIRST[rng.random_range(0..FIRST.len())] as char);
        for _ in 1..len {
            ident.push(REST[rng.random_range(0..REST.len())] as char);
        }
        if !KEYWORDS.contains(&ident.as_str()) {
            return ident;
        }
    }
}

fn random_distinct_idents<const N: usize>(rng: &mut StdRng) -> [String; N] {
    let mut idents = Vec::with_capacity(N);
    while idents.len() < N {
        let ident = random_ident(rng);
        if !idents.iter().any(|existing| existing == &ident) {
            idents.push(ident);
        }
    }
    idents
        .try_into()
        .expect("generated the requested identifiers")
}

fn sanitize_for_artifact(label: &str) -> String {
    label
        .chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '_' })
        .collect()
}
