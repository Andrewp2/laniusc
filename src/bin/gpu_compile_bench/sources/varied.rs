use std::rc::Rc;

use super::{
    DeterministicRng,
    GeneratedExpr,
    GeneratedFunction,
    GeneratedFunctionBody,
    SourceArtifact,
    call_graph_return_generated_expr,
    generated_add,
    generated_call_expr,
    generated_mul,
    generated_score_pair,
    generated_sum,
    varied_short_ident,
};

pub(super) fn make_varied_source_artifact(
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    let mut rng = DeterministicRng::new(seed);
    let names = VariedNames::new(&mut rng);
    let mut functions = String::with_capacity(target_bytes.unwrap_or(lines.saturating_mul(80)));
    let mut main_body = String::with_capacity(lines.saturating_mul(32).min(96 * 1024));
    let mut generated = Vec::<GeneratedFunction>::new();
    let mut expected_stdout = String::new();

    push_varied_prelude(&mut functions, &names);
    let mut line_count = 28usize;
    let mut chunk = 0usize;
    loop {
        let projected_len = functions
            .len()
            .saturating_add(main_body.len())
            .saturating_add(32);
        if target_bytes.is_some_and(|target| projected_len >= target)
            || target_bytes.is_none() && line_count >= lines
        {
            break;
        }

        let prior = (!generated.is_empty()).then(|| {
            let index = rng.index(generated.len());
            generated[index].clone()
        });
        let (function, function_lines) =
            push_varied_function(&mut functions, &names, chunk, prior.as_ref(), &mut rng);
        line_count += function_lines;
        let call = generated_call_expr(&function, chunk + 13, &mut rng);
        let expected = call.eval(&[]);
        expected_stdout.push_str(&expected.to_string());
        expected_stdout.push('\n');
        main_body.push_str("    print(");
        main_body.push_str(&call.source(&[]));
        main_body.push_str(");\n");
        line_count += 1;
        generated.push(function);
        chunk += 1;
    }

    let mut src = String::with_capacity(
        functions
            .len()
            .saturating_add(main_body.len())
            .saturating_add(32),
    );
    src.push_str(&functions);
    src.push_str("fn main() {\n");
    src.push_str(&main_body);
    src.push_str("    return 0;\n");
    src.push_str("}\n");
    SourceArtifact::single(src, Some(expected_stdout))
}

struct VariedNames {
    pair_type: String,
    choice_type: String,
    left_field: String,
    right_field: String,
    left_variant: String,
    right_variant: String,
    make_pair_fn: String,
    score_pair_fn: String,
    sum4_fn: String,
    pick_fn: String,
    make_left_param: String,
    make_right_param: String,
    score_param: String,
    sum_param: String,
    pick_values_param: String,
    pick_len_param: String,
    pick_index_param: String,
    pick_fallback_param: String,
}

impl VariedNames {
    fn new(rng: &mut DeterministicRng) -> Self {
        Self {
            pair_type: varied_short_ident("t", 0, rng),
            choice_type: varied_short_ident("e", 15, rng),
            left_field: varied_short_ident("f", 1, rng),
            right_field: varied_short_ident("f", 2, rng),
            left_variant: varied_short_ident("v", 16, rng),
            right_variant: varied_short_ident("v", 17, rng),
            make_pair_fn: varied_short_ident("g", 3, rng),
            score_pair_fn: varied_short_ident("g", 4, rng),
            sum4_fn: varied_short_ident("g", 5, rng),
            pick_fn: varied_short_ident("g", 6, rng),
            make_left_param: varied_short_ident("p", 7, rng),
            make_right_param: varied_short_ident("p", 8, rng),
            score_param: varied_short_ident("p", 9, rng),
            sum_param: varied_short_ident("p", 10, rng),
            pick_values_param: varied_short_ident("p", 11, rng),
            pick_len_param: varied_short_ident("p", 12, rng),
            pick_index_param: varied_short_ident("p", 13, rng),
            pick_fallback_param: varied_short_ident("p", 14, rng),
        }
    }
}

fn varied_short_params(chunk: usize, arity: usize, rng: &mut DeterministicRng) -> Vec<String> {
    (0..arity)
        .map(|param_i| {
            varied_short_ident("p", chunk.saturating_mul(8).saturating_add(param_i), rng)
        })
        .collect()
}

fn push_varied_prelude(src: &mut String, names: &VariedNames) {
    src.push_str("enum ");
    src.push_str(&names.choice_type);
    src.push_str(" {\n    ");
    src.push_str(&names.left_variant);
    src.push_str(",\n    ");
    src.push_str(&names.right_variant);
    src.push_str(",\n}\n");

    src.push_str("struct ");
    src.push_str(&names.pair_type);
    src.push_str(" {\n    ");
    src.push_str(&names.left_field);
    src.push_str(": i32,\n    ");
    src.push_str(&names.right_field);
    src.push_str(": i32,\n}\n");

    src.push_str("fn ");
    src.push_str(&names.make_pair_fn);
    src.push('(');
    src.push_str(&names.make_left_param);
    src.push_str(": i32, ");
    src.push_str(&names.make_right_param);
    src.push_str(": i32) -> ");
    src.push_str(&names.pair_type);
    src.push_str(" {\n    return ");
    src.push_str(&names.pair_type);
    src.push_str(" { ");
    src.push_str(&names.left_field);
    src.push_str(": ");
    src.push_str(&names.make_left_param);
    src.push_str(", ");
    src.push_str(&names.right_field);
    src.push_str(": ");
    src.push_str(&names.make_right_param);
    src.push_str(" };\n}\n");

    src.push_str("fn ");
    src.push_str(&names.score_pair_fn);
    src.push('(');
    src.push_str(&names.score_param);
    src.push_str(": ");
    src.push_str(&names.pair_type);
    src.push_str(") -> i32 {\n    return ");
    src.push_str(&names.score_param);
    src.push('.');
    src.push_str(&names.left_field);
    src.push_str(" * 3 + ");
    src.push_str(&names.score_param);
    src.push('.');
    src.push_str(&names.right_field);
    src.push_str(";\n}\n");

    src.push_str("fn ");
    src.push_str(&names.sum4_fn);
    src.push('(');
    src.push_str(&names.sum_param);
    src.push_str(": [i32; 4]) -> i32 {\n    return ");
    src.push_str(&names.sum_param);
    src.push_str("[0] + ");
    src.push_str(&names.sum_param);
    src.push_str("[1] + ");
    src.push_str(&names.sum_param);
    src.push_str("[2] + ");
    src.push_str(&names.sum_param);
    src.push_str("[3];\n}\n");

    src.push_str("fn ");
    src.push_str(&names.pick_fn);
    src.push('(');
    src.push_str(&names.pick_values_param);
    src.push_str(": [i32], ");
    src.push_str(&names.pick_len_param);
    src.push_str(": i32, ");
    src.push_str(&names.pick_index_param);
    src.push_str(": i32, ");
    src.push_str(&names.pick_fallback_param);
    src.push_str(": i32) -> i32 {\n    if (");
    src.push_str(&names.pick_index_param);
    src.push_str(" >= ");
    src.push_str(&names.pick_len_param);
    src.push_str(") {\n        return ");
    src.push_str(&names.pick_fallback_param);
    src.push_str(";\n    } else {\n        return ");
    src.push_str(&names.pick_values_param);
    src.push('[');
    src.push_str(&names.pick_index_param);
    src.push_str("];\n    }\n}\n");
}

fn push_varied_function(
    src: &mut String,
    names: &VariedNames,
    chunk: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunction, usize) {
    let arity = chunk % 5;
    let name = varied_short_ident("h", chunk + 100, rng);
    let params = varied_short_params(chunk + 1000, arity, rng);

    src.push_str("fn ");
    src.push_str(&name);
    src.push('(');
    for param_i in 0..arity {
        if param_i != 0 {
            src.push_str(", ");
        }
        src.push_str(&params[param_i]);
        src.push_str(": i32");
    }
    src.push_str(") -> i32 {\n");
    let (body, body_lines) =
        push_varied_function_body(src, names, chunk, arity, &params, prior, rng);
    src.push_str("}\n");

    (
        GeneratedFunction {
            name,
            arity,
            body: Some(Rc::new(body)),
        },
        body_lines + 2,
    )
}

fn push_varied_function_body(
    src: &mut String,
    names: &VariedNames,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    match chunk % 11 {
        0 => push_varied_scalar_return(src, chunk, arity, params, prior, rng),
        1 => push_varied_branch_return(src, chunk, arity, params, prior, rng),
        2 => push_varied_local_chain(src, names, chunk, arity, params, prior, rng),
        3 => push_varied_array_return(src, names, chunk, arity, params, rng),
        4 => push_varied_struct_return(src, names, chunk, arity, params, rng),
        5 => push_varied_slice_return(src, names, chunk, arity, params, rng),
        6 => push_varied_while_return(src, chunk, arity, params, rng),
        7 => push_varied_for_return(src, chunk, arity, params, rng),
        8 => push_varied_unsigned_branch_return(src, chunk, arity, params, rng),
        9 => push_varied_nested_unsigned_branch_return(src, chunk, arity, params, rng),
        _ => push_varied_enum_match_return(src, names, chunk, arity, params, prior, rng),
    }
}

fn varied_base_generated_expr(
    chunk: usize,
    arity: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> GeneratedExpr {
    if let Some(prior) = prior
        && chunk % 4 == 0
    {
        let call = generated_call_expr(prior, chunk + 21, rng);
        return if arity == 0 {
            call
        } else {
            GeneratedExpr::Add(Box::new(call), Box::new(GeneratedExpr::Param(0)))
        };
    }
    call_graph_return_generated_expr(chunk, arity, None, rng)
}

fn push_varied_scalar_return(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let expr = varied_base_generated_expr(chunk, arity, prior, rng);
    src.push_str("    return ");
    src.push_str(&expr.source(params));
    src.push_str(";\n");
    (GeneratedFunctionBody::Return(expr), 1)
}

fn push_varied_branch_return(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let left = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 17) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let right = GeneratedExpr::Literal((rng.small_int() % 17) as i32);
    let then_expr = varied_base_generated_expr(chunk + 1, arity, prior, rng);
    let else_expr = varied_base_generated_expr(chunk + 2, arity, prior, rng);
    src.push_str("    if (");
    src.push_str(&left.source(params));
    src.push_str(" < ");
    src.push_str(&right.source(params));
    src.push_str(") {\n        return ");
    src.push_str(&then_expr.source(params));
    src.push_str(";\n    } else {\n        return ");
    src.push_str(&else_expr.source(params));
    src.push_str(";\n    }\n");
    (
        GeneratedFunctionBody::LessBranch {
            left,
            right,
            then_expr,
            else_expr,
        },
        5,
    )
}

fn push_varied_local_chain(
    src: &mut String,
    names: &VariedNames,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let local = varied_short_ident("l", chunk, rng);
    let pair = varied_short_ident("q", chunk + 20, rng);
    let base = varied_base_generated_expr(chunk + 3, arity, prior, rng);
    let right = GeneratedExpr::Literal((rng.small_int() % 31) as i32);
    src.push_str("    let ");
    src.push_str(&local);
    src.push_str(": i32 = ");
    src.push_str(&base.source(params));
    src.push_str(";\n    let ");
    src.push_str(&pair);
    src.push_str(": ");
    src.push_str(&names.pair_type);
    src.push_str(" = ");
    src.push_str(&names.make_pair_fn);
    src.push('(');
    src.push_str(&local);
    src.push_str(", ");
    src.push_str(&right.source(params));
    src.push_str(");\n    return ");
    src.push_str(&names.score_pair_fn);
    src.push('(');
    src.push_str(&pair);
    src.push_str(");\n");
    (
        GeneratedFunctionBody::Return(generated_score_pair(base, right)),
        3,
    )
}

fn push_varied_array_return(
    src: &mut String,
    names: &VariedNames,
    chunk: usize,
    arity: usize,
    params: &[String],
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let values = varied_short_ident("a", chunk, rng);
    let head = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 31) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let mut elements = vec![head];
    src.push_str("    let ");
    src.push_str(&values);
    src.push_str(": [i32; 4] = [");
    src.push_str(&elements[0].source(params));
    for _ in 1..4 {
        let element = GeneratedExpr::Literal((rng.small_int() % 31) as i32);
        src.push_str(", ");
        src.push_str(&element.source(params));
        elements.push(element);
    }
    src.push_str("];\n    return ");
    src.push_str(&names.sum4_fn);
    src.push('(');
    src.push_str(&values);
    src.push_str(") + ");
    src.push_str(&(chunk % 11).to_string());
    src.push_str(";\n");
    (
        GeneratedFunctionBody::Return(generated_add(
            generated_sum(elements),
            GeneratedExpr::Literal((chunk % 11) as i32),
        )),
        2,
    )
}

fn push_varied_struct_return(
    src: &mut String,
    names: &VariedNames,
    chunk: usize,
    arity: usize,
    params: &[String],
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let pair = varied_short_ident("s", chunk, rng);
    let left = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 23) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let right = if arity >= 2 {
        GeneratedExpr::Param(1)
    } else {
        GeneratedExpr::Literal((rng.small_int() % 23) as i32)
    };
    src.push_str("    let ");
    src.push_str(&pair);
    src.push_str(": ");
    src.push_str(&names.pair_type);
    src.push_str(" = ");
    src.push_str(&names.make_pair_fn);
    src.push('(');
    src.push_str(&left.source(params));
    src.push_str(", ");
    src.push_str(&right.source(params));
    src.push_str(");\n    return ");
    src.push_str(&names.score_pair_fn);
    src.push('(');
    src.push_str(&pair);
    src.push_str(");\n");
    (
        GeneratedFunctionBody::Return(generated_score_pair(left, right)),
        2,
    )
}

fn push_varied_slice_return(
    src: &mut String,
    names: &VariedNames,
    chunk: usize,
    arity: usize,
    params: &[String],
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let values = varied_short_ident("q", chunk, rng);
    let fallback = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 29) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let mut elements = Vec::with_capacity(4);
    src.push_str("    let ");
    src.push_str(&values);
    src.push_str(": [i32; 4] = [");
    for value_i in 0..4 {
        if value_i != 0 {
            src.push_str(", ");
        }
        let element = GeneratedExpr::Literal((rng.small_int() % 29) as i32);
        src.push_str(&element.source(params));
        elements.push(element);
    }
    src.push_str("];\n    return ");
    src.push_str(&names.pick_fn);
    src.push('(');
    src.push_str(&values);
    src.push_str(", 4, ");
    src.push_str(&(chunk % 6).to_string());
    src.push_str(", ");
    src.push_str(&fallback.source(params));
    src.push_str(");\n");
    let result = elements
        .get(chunk % 6)
        .cloned()
        .unwrap_or_else(|| fallback.clone());
    (GeneratedFunctionBody::Return(result), 2)
}

fn push_varied_while_return(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let index = varied_short_ident("i", chunk, rng);
    let total = varied_short_ident("w", chunk, rng);
    let addend = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 7 + 1) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let initial = GeneratedExpr::Literal((rng.small_int() % 11) as i32);
    let limit = (chunk % 5 + 1) as i32;
    src.push_str("    let ");
    src.push_str(&index);
    src.push_str(": i32 = 0;\n    let ");
    src.push_str(&total);
    src.push_str(": i32 = ");
    src.push_str(&initial.source(params));
    src.push_str(";\n    while (");
    src.push_str(&index);
    src.push_str(" < ");
    src.push_str(&limit.to_string());
    src.push_str(") {\n        ");
    src.push_str(&total);
    src.push_str(" += ");
    src.push_str(&addend.source(params));
    src.push_str(";\n        ");
    src.push_str(&index);
    src.push_str(" += 1;\n    }\n    return ");
    src.push_str(&total);
    src.push_str(";\n");
    (
        GeneratedFunctionBody::Return(generated_add(
            initial,
            generated_mul(GeneratedExpr::Literal(limit), addend),
        )),
        7,
    )
}

fn push_varied_for_return(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let values = varied_short_ident("r", chunk, rng);
    let value = varied_short_ident("v", chunk, rng);
    let total = varied_short_ident("u", chunk, rng);
    let head = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 19) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let mut elements = vec![head];
    src.push_str("    let ");
    src.push_str(&values);
    src.push_str(": [i32; 4] = [");
    src.push_str(&elements[0].source(params));
    for _ in 1..4 {
        let element = GeneratedExpr::Literal((rng.small_int() % 19) as i32);
        src.push_str(", ");
        src.push_str(&element.source(params));
        elements.push(element);
    }
    src.push_str("];\n    let ");
    src.push_str(&total);
    src.push_str(": i32 = 0;\n    for ");
    src.push_str(&value);
    src.push_str(" in ");
    src.push_str(&values);
    src.push_str(" {\n        ");
    src.push_str(&total);
    src.push_str(" += ");
    src.push_str(&value);
    src.push_str(";\n    }\n    return ");
    src.push_str(&total);
    src.push_str(";\n");
    (GeneratedFunctionBody::Return(generated_sum(elements)), 6)
}

fn push_varied_unsigned_branch_return(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let left = varied_short_ident("u", chunk, rng);
    let right = varied_short_ident("u", chunk + 41, rng);
    let then_expr = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 37) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let else_expr = GeneratedExpr::Literal((rng.small_int() % 37) as i32);
    src.push_str("    let ");
    src.push_str(&left);
    src.push_str(": u32 = 4294967295;\n    let ");
    src.push_str(&right);
    src.push_str(": u32 = ");
    src.push_str(&(chunk % 97 + 1).to_string());
    src.push_str(";\n    if (");
    src.push_str(&left);
    src.push_str(" > ");
    src.push_str(&right);
    src.push_str(") {\n        return ");
    src.push_str(&then_expr.source(params));
    src.push_str(";\n    } else {\n        return ");
    src.push_str(&else_expr.source(params));
    src.push_str(";\n    }\n");
    (GeneratedFunctionBody::Return(then_expr), 7)
}

fn push_varied_nested_unsigned_branch_return(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let left = varied_short_ident("u", chunk, rng);
    let right = varied_short_ident("u", chunk + 43, rng);
    let depth = 9 + rng.index(8);
    let then_expr = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 37) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let else_expr = GeneratedExpr::Literal((rng.small_int() % 37) as i32);
    src.push_str("    let ");
    src.push_str(&left);
    src.push_str(": u32 = 4294967295;\n    let ");
    src.push_str(&right);
    src.push_str(": u32 = ");
    src.push_str(&(chunk % 97 + 1).to_string());
    src.push_str(";\n    if (");
    for _ in 0..depth {
        src.push('(');
    }
    src.push_str(&left);
    for _ in 0..depth {
        src.push_str(" + 0)");
    }
    src.push_str(" > ");
    src.push_str(&right);
    src.push_str(") {\n        return ");
    src.push_str(&then_expr.source(params));
    src.push_str(";\n    } else {\n        return ");
    src.push_str(&else_expr.source(params));
    src.push_str(";\n    }\n");
    (GeneratedFunctionBody::Return(then_expr), 7)
}

fn push_varied_enum_match_return(
    src: &mut String,
    names: &VariedNames,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let choice = varied_short_ident("m", chunk, rng);
    let variant = if chunk % 2 == 0 {
        &names.left_variant
    } else {
        &names.right_variant
    };
    let left_expr = varied_base_generated_expr(chunk + 5, arity, prior, rng);
    let right_expr = varied_base_generated_expr(chunk + 6, arity, prior, rng);
    src.push_str("    let ");
    src.push_str(&choice);
    src.push_str(": ");
    src.push_str(&names.choice_type);
    src.push_str(" = ");
    src.push_str(variant);
    src.push_str(";\n    return match (");
    src.push_str(&choice);
    src.push_str(") {\n        ");
    src.push_str(&names.left_variant);
    src.push_str(" -> ");
    src.push_str(&left_expr.source(params));
    src.push_str(",\n        ");
    src.push_str(&names.right_variant);
    src.push_str(" -> ");
    src.push_str(&right_expr.source(params));
    src.push_str(",\n    };\n");
    let result = if chunk % 2 == 0 {
        left_expr
    } else {
        right_expr
    };
    (GeneratedFunctionBody::Return(result), 6)
}
