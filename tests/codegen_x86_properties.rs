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
    cases.push(generated_bool_branch_program(&mut rng));

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

    vec![
        identity_local,
        add_literals,
        binary_args,
        nested_call,
        call_let_chain,
    ]
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

fn i32_lit(value: i32) -> String {
    value.to_string()
}

fn bool_lit(value: bool) -> &'static str {
    if value { "true" } else { "false" }
}

fn exit_status(value: i32) -> i32 {
    (value as u32 & 0xff) as i32
}

fn random_ident(rng: &mut StdRng) -> String {
    const FIRST: &[u8] = b"abcdefghijklmnopqrstuvwxyz";
    const REST: &[u8] = b"abcdefghijklmnopqrstuvwxyz0123456789_";
    const KEYWORDS: &[&str] = &[
        "fn", "main", "let", "return", "true", "false", "if", "else", "i32", "bool",
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
