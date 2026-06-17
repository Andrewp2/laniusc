use super::{DeterministicRng, SourceArtifact, append_expected_print, wrap_body_in_main};

pub(super) fn make_mixed_source_artifact(
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    const MIXED_CHUNKS_PER_HELPER: usize = 32;

    let mut functions = String::with_capacity(target_bytes.unwrap_or(lines.saturating_mul(48)));
    let mut main_body = String::new();
    let mut rng = DeterministicRng::new(seed);
    let mut expected_stdout = String::new();
    let mut line_count = 0usize;
    let mut chunk = 0usize;
    let mut helper_i = 0usize;
    loop {
        let generated_len = functions.len().saturating_add(main_body.len());
        if target_bytes.is_some_and(|target| generated_len >= target)
            || target_bytes.is_none() && line_count >= lines
        {
            break;
        }

        let mut helper_body = String::new();
        let mut helper_chunks = 0usize;
        while helper_chunks < MIXED_CHUNKS_PER_HELPER
            && target_bytes.is_none_or(|target| {
                functions
                    .len()
                    .saturating_add(main_body.len())
                    .saturating_add(helper_body.len())
                    < target
            })
            && (target_bytes.is_some() || line_count < lines)
        {
            line_count += push_mixed_chunk(&mut helper_body, chunk, &mut rng, &mut expected_stdout);
            chunk += 1;
            helper_chunks += 1;
        }

        if helper_chunks == 0 {
            break;
        }

        functions.push_str("fn mix_helper");
        functions.push_str(&helper_i.to_string());
        functions.push_str("() -> i32 {\n");
        functions.push_str(&helper_body);
        if !helper_body.ends_with('\n') {
            functions.push('\n');
        }
        functions.push_str("    return 0;\n}\n");

        main_body.push_str("let mix_result");
        main_body.push_str(&helper_i.to_string());
        main_body.push_str(" = mix_helper");
        main_body.push_str(&helper_i.to_string());
        main_body.push_str("();\n");
        helper_i += 1;
    }
    let mut source = functions;
    source.push_str(&wrap_body_in_main(&main_body));
    SourceArtifact::single(source, Some(expected_stdout))
}

fn push_mixed_chunk(
    src: &mut String,
    chunk: usize,
    rng: &mut DeterministicRng,
    expected_stdout: &mut String,
) -> usize {
    if chunk >= 3 {
        return push_arithmetic_chunk(src, chunk, rng, expected_stdout);
    }

    match chunk % 4 {
        0 => push_bool_let_chunk(src, chunk, rng, expected_stdout),
        1 => push_if_else_chunk(src, chunk, rng, expected_stdout),
        2 => push_compare_print_chunk(src, chunk, rng, expected_stdout),
        _ => push_logic_chunk(src, chunk, rng, expected_stdout),
    }
}
fn push_bool_let_chunk(
    src: &mut String,
    chunk: usize,
    rng: &mut DeterministicRng,
    expected_stdout: &mut String,
) -> usize {
    let a = rng.small_int();
    let b = rng.small_int();
    if chunk % 32 != 0 {
        let c = rng.small_int();
        let d = rng.small_int();
        append_expected_print(expected_stdout, if a < b && c != d { a } else { b } as i32);
        src.push_str(&format!("if (({a} < {b}) && !({c} == {d})) {{\n"));
        src.push_str(&format!("    print({a});\n"));
        src.push_str("} else {\n");
        src.push_str(&format!("    print({b});\n"));
        src.push_str("}\n");
        return 5;
    }

    let c = rng.small_int();
    let d = rng.small_int();
    append_expected_print(expected_stdout, if a < b && c != d { a } else { b } as i32);
    src.push_str(&format!(
        "let flag{chunk}: bool = ({a} < {b}) && !({c} == {d});\n"
    ));
    src.push_str(&format!("if (flag{chunk}) {{\n"));
    src.push_str(&format!("    print({a});\n"));
    src.push_str("} else {\n");
    src.push_str(&format!("    print({b});\n"));
    src.push_str("}\n");
    6
}

fn push_if_else_chunk(
    src: &mut String,
    chunk: usize,
    rng: &mut DeterministicRng,
    expected_stdout: &mut String,
) -> usize {
    let a = rng.small_int();
    let b = rng.small_int();
    append_expected_print(expected_stdout, if a <= b || b == a { a } else { b } as i32);
    src.push_str(&format!("if (({a} <= {b}) || !({b} != {a})) {{\n"));
    src.push_str(&format!("    print({a});\n"));
    src.push_str("} else {\n");
    src.push_str(&format!("    print({b});\n"));
    src.push_str("}\n");
    let _ = chunk;
    5
}

fn push_arithmetic_chunk(
    src: &mut String,
    chunk: usize,
    rng: &mut DeterministicRng,
    expected_stdout: &mut String,
) -> usize {
    let a = rng.small_int();
    let b = rng.small_int();
    let c = rng.small_int();
    let d = rng.small_int();
    match chunk % 3 {
        0 => {
            append_expected_print(
                expected_stdout,
                (a as i32)
                    .wrapping_add(b as i32)
                    .wrapping_mul((c as i32).wrapping_sub(d as i32)),
            );
            src.push_str(&format!(
                "let mix{chunk}: i32 = ({} + {}) * ({} - {});\n",
                a, b, c, d
            ));
            src.push_str(&format!("print(mix{chunk});\n"));
        }
        1 => {
            append_expected_print(expected_stdout, ((a & b) | (c ^ d)) as i32);
            src.push_str(&format!(
                "let mix{chunk}: i32 = ({} & {}) | ({} ^ {});\n",
                a, b, c, d
            ));
            src.push_str(&format!("print(mix{chunk});\n"));
        }
        _ => {
            append_expected_print(
                expected_stdout,
                ((a << 1).wrapping_add(b >> 1).wrapping_add(c)) as i32,
            );
            src.push_str(&format!(
                "let mix{chunk}: i32 = ({} << 1) + ({} >> 1);\n",
                a, b
            ));
            src.push_str(&format!("print(mix{chunk} + {});\n", c));
        }
    }
    2
}

fn push_compare_print_chunk(
    src: &mut String,
    chunk: usize,
    rng: &mut DeterministicRng,
    expected_stdout: &mut String,
) -> usize {
    let a = rng.small_int();
    let b = rng.small_int();
    let c = rng.small_int();
    append_expected_print(expected_stdout, if a >= b || a == c { a } else { c } as i32);
    src.push_str(&format!("if (({a} >= {b}) || ({a} == {c})) {{\n"));
    src.push_str(&format!("    print({a});\n"));
    src.push_str("} else {\n");
    src.push_str(&format!("    print({c});\n"));
    src.push_str("}\n");
    let _ = chunk;
    5
}

fn push_logic_chunk(
    src: &mut String,
    chunk: usize,
    rng: &mut DeterministicRng,
    expected_stdout: &mut String,
) -> usize {
    let a = rng.small_int();
    let b = rng.small_int();
    let c = rng.small_int();
    append_expected_print(expected_stdout, if a <= b || b > c { b } else { c } as i32);
    src.push_str(&format!("if (({a} <= {b}) || ({b} > {c})) {{\n"));
    src.push_str(&format!("    print({b});\n"));
    src.push_str("} else {\n");
    src.push_str(&format!("    print({c});\n"));
    src.push_str("}\n");
    let _ = chunk;
    5
}
