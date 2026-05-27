use super::{DeterministicRng, SourceArtifact, varied_short_ident};

struct LongFunctionSimulation {
    acc: i32,
    expected_stdout: String,
}

impl LongFunctionSimulation {
    fn add(&mut self, value: i32) {
        self.acc = self.acc.wrapping_add(value);
    }

    fn sub(&mut self, value: i32) {
        self.acc = self.acc.wrapping_sub(value);
    }

    fn print(&mut self, value: i32) {
        self.expected_stdout.push_str(&value.to_string());
        self.expected_stdout.push('\n');
    }
}

pub(super) fn make_long_function_source_artifact(
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    let mut rng = DeterministicRng::new(seed);
    let pair_type = varied_short_ident("t", 0, &mut rng);
    let left_field = varied_short_ident("f", 1, &mut rng);
    let right_field = varied_short_ident("f", 2, &mut rng);
    let helper_fn = varied_short_ident("h", 3, &mut rng);
    let helper_param = varied_short_ident("p", 4, &mut rng);
    let acc_name = varied_short_ident("a", 5, &mut rng);
    let mut src = String::with_capacity(target_bytes.unwrap_or(lines.saturating_mul(48)));
    let mut sim = LongFunctionSimulation {
        acc: 0,
        expected_stdout: String::new(),
    };

    src.push_str("struct ");
    src.push_str(&pair_type);
    src.push_str(" {\n    ");
    src.push_str(&left_field);
    src.push_str(": i32,\n    ");
    src.push_str(&right_field);
    src.push_str(": i32,\n}\nfn ");
    src.push_str(&helper_fn);
    src.push('(');
    src.push_str(&helper_param);
    src.push_str(": i32) -> i32 {\n    return ");
    src.push_str(&helper_param);
    src.push_str(" + 1;\n}\nfn main() {\n    let ");
    src.push_str(&acc_name);
    src.push_str(": i32 = 0;\n");

    let mut line_count = 13usize;
    let mut chunk = 0usize;
    loop {
        if target_bytes.is_some_and(|target| src.len() >= target)
            || target_bytes.is_none() && line_count >= lines
        {
            break;
        }
        line_count += push_long_function_chunk(
            &mut src,
            chunk,
            &pair_type,
            &left_field,
            &right_field,
            &helper_fn,
            &acc_name,
            &mut rng,
            &mut sim,
        );
        chunk += 1;
    }

    src.push_str("    return 0;\n}\n");
    SourceArtifact::single(src, Some(sim.expected_stdout))
}

fn push_long_function_chunk(
    src: &mut String,
    chunk: usize,
    pair_type: &str,
    left_field: &str,
    right_field: &str,
    helper_fn: &str,
    acc_name: &str,
    rng: &mut DeterministicRng,
    sim: &mut LongFunctionSimulation,
) -> usize {
    match chunk % 6 {
        0 => push_long_nested_arithmetic(src, chunk, helper_fn, acc_name, rng, sim),
        1 => push_long_branch(src, chunk, acc_name, rng, sim),
        2 => push_long_array_loop(src, chunk, acc_name, rng, sim),
        3 => push_long_struct_use(
            src,
            chunk,
            pair_type,
            left_field,
            right_field,
            acc_name,
            rng,
            sim,
        ),
        4 => push_long_while(src, chunk, acc_name, rng, sim),
        _ => push_long_print(src, acc_name, rng, sim),
    }
}

fn push_long_nested_arithmetic(
    src: &mut String,
    chunk: usize,
    helper_fn: &str,
    acc_name: &str,
    rng: &mut DeterministicRng,
    sim: &mut LongFunctionSimulation,
) -> usize {
    let local = varied_short_ident("l", chunk, rng);
    let a = rng.small_int() % 31;
    let b = rng.small_int() % 17;
    let c = rng.small_int() % 9;
    let d = rng.small_int() % 7;
    let helper_arg = sim
        .acc
        .wrapping_add(a as i32)
        .wrapping_mul((b as i32).wrapping_sub(c as i32))
        .wrapping_add(d as i32);
    sim.add(helper_arg.wrapping_add(1));
    src.push_str("    let ");
    src.push_str(&local);
    src.push_str(": i32 = ");
    src.push_str(helper_fn);
    src.push_str("(((");
    src.push_str(acc_name);
    src.push_str(" + ");
    src.push_str(&a.to_string());
    src.push_str(") * (");
    src.push_str(&b.to_string());
    src.push_str(" - ");
    src.push_str(&c.to_string());
    src.push_str(")) + ");
    src.push_str(&d.to_string());
    src.push_str(");\n    ");
    src.push_str(acc_name);
    src.push_str(" += ");
    src.push_str(&local);
    src.push_str(";\n");
    2
}

fn push_long_branch(
    src: &mut String,
    chunk: usize,
    acc_name: &str,
    rng: &mut DeterministicRng,
    sim: &mut LongFunctionSimulation,
) -> usize {
    let threshold = (chunk % 97 + 1) as i32;
    let then_value = (rng.small_int() % 13 + 1) as i32;
    let else_value = (rng.small_int() % 11 + 1) as i32;
    if (sim.acc & 1) == 0 || sim.acc < threshold {
        sim.add(then_value);
    } else {
        sim.sub(else_value);
    }
    src.push_str("    if ((");
    src.push_str(acc_name);
    src.push_str(" & 1) == 0 || ");
    src.push_str(acc_name);
    src.push_str(" < ");
    src.push_str(&threshold.to_string());
    src.push_str(") {\n        ");
    src.push_str(acc_name);
    src.push_str(" += ");
    src.push_str(&then_value.to_string());
    src.push_str(";\n    } else {\n        ");
    src.push_str(acc_name);
    src.push_str(" -= ");
    src.push_str(&else_value.to_string());
    src.push_str(";\n    }\n");
    5
}

fn push_long_array_loop(
    src: &mut String,
    chunk: usize,
    acc_name: &str,
    rng: &mut DeterministicRng,
    sim: &mut LongFunctionSimulation,
) -> usize {
    let values = varied_short_ident("r", chunk, rng);
    let value = varied_short_ident("v", chunk, rng);
    let old_acc = sim.acc;
    let mut elements_sum = old_acc;
    src.push_str("    let ");
    src.push_str(&values);
    src.push_str(": [i32; 4] = [");
    src.push_str(acc_name);
    src.push_str(", ");
    for item_i in 0..3 {
        if item_i != 0 {
            src.push_str(", ");
        }
        let element = (rng.small_int() % 17) as i32;
        elements_sum = elements_sum.wrapping_add(element);
        src.push_str(&element.to_string());
    }
    sim.add(elements_sum);
    src.push_str("];\n    for ");
    src.push_str(&value);
    src.push_str(" in ");
    src.push_str(&values);
    src.push_str(" {\n        ");
    src.push_str(acc_name);
    src.push_str(" += ");
    src.push_str(&value);
    src.push_str(";\n    }\n");
    5
}

fn push_long_struct_use(
    src: &mut String,
    chunk: usize,
    pair_type: &str,
    left_field: &str,
    right_field: &str,
    acc_name: &str,
    rng: &mut DeterministicRng,
    sim: &mut LongFunctionSimulation,
) -> usize {
    let local = varied_short_ident("s", chunk, rng);
    let right_value = (rng.small_int() % 23) as i32;
    sim.add(sim.acc.wrapping_add(right_value));
    src.push_str("    let ");
    src.push_str(&local);
    src.push_str(": ");
    src.push_str(pair_type);
    src.push_str(" = ");
    src.push_str(pair_type);
    src.push_str(" { ");
    src.push_str(left_field);
    src.push_str(": ");
    src.push_str(acc_name);
    src.push_str(", ");
    src.push_str(right_field);
    src.push_str(": ");
    src.push_str(&right_value.to_string());
    src.push_str(" };\n    ");
    src.push_str(acc_name);
    src.push_str(" += ");
    src.push_str(&local);
    src.push('.');
    src.push_str(left_field);
    src.push_str(" + ");
    src.push_str(&local);
    src.push('.');
    src.push_str(right_field);
    src.push_str(";\n");
    2
}

fn push_long_while(
    src: &mut String,
    chunk: usize,
    acc_name: &str,
    rng: &mut DeterministicRng,
    sim: &mut LongFunctionSimulation,
) -> usize {
    let index = varied_short_ident("i", chunk, rng);
    let limit = (chunk % 3 + 1) as i32;
    let step = (rng.small_int() % 5 + 1) as i32;
    sim.add(limit.wrapping_mul(step));
    src.push_str("    let ");
    src.push_str(&index);
    src.push_str(": i32 = 0;\n    while (");
    src.push_str(&index);
    src.push_str(" < ");
    src.push_str(&limit.to_string());
    src.push_str(") {\n        ");
    src.push_str(acc_name);
    src.push_str(" += ");
    src.push_str(&step.to_string());
    src.push_str(";\n        ");
    src.push_str(&index);
    src.push_str(" += 1;\n    }\n");
    6
}

fn push_long_print(
    src: &mut String,
    acc_name: &str,
    rng: &mut DeterministicRng,
    sim: &mut LongFunctionSimulation,
) -> usize {
    let offset = (rng.small_int() % 7) as i32;
    sim.print(sim.acc.wrapping_add(offset));
    src.push_str("    print(");
    src.push_str(acc_name);
    src.push_str(" + ");
    src.push_str(&offset.to_string());
    src.push_str(");\n");
    1
}
