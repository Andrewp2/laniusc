use std::rc::Rc;

use laniusc_compiler::codegen::unit::SourcePackLibraryDependency;

use super::SourceMode;

#[path = "sources/long_function.rs"]
mod long_function;
#[path = "sources/mixed.rs"]
mod mixed;
#[path = "sources/module_pack.rs"]
mod module_pack;
#[path = "sources/varied.rs"]
mod varied;
use long_function::make_long_function_source_artifact;
use mixed::make_mixed_source_artifact;
use module_pack::make_module_pack_source_artifact;
use varied::make_varied_source_artifact;

pub(super) struct SourceArtifact {
    pub(super) source: String,
    pub(super) sources: Vec<String>,
    pub(super) library_ids: Vec<u32>,
    pub(super) library_dependencies: Vec<SourcePackLibraryDependency>,
    pub(super) expected_stdout: Option<String>,
}

impl SourceArtifact {
    fn single(source: String, expected_stdout: Option<String>) -> Self {
        Self {
            sources: vec![source.clone()],
            library_ids: vec![0],
            library_dependencies: Vec::new(),
            source,
            expected_stdout,
        }
    }

    fn source_pack_with_libraries(
        sources: Vec<String>,
        library_ids: Vec<u32>,
        library_dependencies: Vec<SourcePackLibraryDependency>,
        expected_stdout: Option<String>,
    ) -> Self {
        assert_eq!(
            sources.len(),
            library_ids.len(),
            "source-pack library id count must match source count"
        );
        let source = sources.join("");
        Self {
            source,
            sources,
            library_ids,
            library_dependencies,
            expected_stdout,
        }
    }
}

pub(super) fn make_source_artifact(
    source_mode: SourceMode,
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    let (source, expected_stdout) = match source_mode {
        SourceMode::SimpleLets => (
            wrap_body_in_main(&make_simple_let_source(lines, target_bytes)),
            Some(String::new()),
        ),
        SourceMode::Mixed => {
            let SourceArtifact {
                source,
                expected_stdout,
                ..
            } = make_mixed_source_artifact(lines, target_bytes, seed);
            (source, expected_stdout)
        }
        SourceMode::CallGraph => {
            let SourceArtifact {
                source,
                expected_stdout,
                ..
            } = make_call_graph_source_artifact(lines, target_bytes, seed);
            (source, expected_stdout)
        }
        SourceMode::ExprDense => {
            let SourceArtifact {
                source,
                expected_stdout,
                ..
            } = make_expr_dense_source_artifact(lines, target_bytes, seed);
            (source, expected_stdout)
        }
        SourceMode::AbiCalls => {
            let SourceArtifact {
                source,
                expected_stdout,
                ..
            } = make_abi_call_source_artifact(lines, target_bytes, seed);
            (source, expected_stdout)
        }
        SourceMode::Varied => {
            let SourceArtifact {
                source,
                expected_stdout,
                ..
            } = make_varied_source_artifact(lines, target_bytes, seed);
            (source, expected_stdout)
        }
        SourceMode::LongFunction => {
            let SourceArtifact {
                source,
                expected_stdout,
                ..
            } = make_long_function_source_artifact(lines, target_bytes, seed);
            (source, expected_stdout)
        }
        SourceMode::ModulePack => {
            return make_module_pack_source_artifact(lines, target_bytes, seed);
        }
        SourceMode::All => unreachable!("suite mode expands before source generation"),
    };
    SourceArtifact::single(source, expected_stdout)
}

fn wrap_body_in_main(body: &str) -> String {
    let mut src = String::with_capacity(body.len().saturating_add(16));
    src.push_str("fn main() {\n");
    src.push_str(body);
    if !body.ends_with('\n') {
        src.push('\n');
    }
    src.push_str("    return 0;\n");
    src.push_str("}\n");
    src
}

fn make_simple_let_source(lines: usize, target_bytes: Option<usize>) -> String {
    if let Some(target_bytes) = target_bytes {
        let mut src = String::with_capacity(target_bytes.saturating_add(128));
        let mut i = 0usize;
        while src.len() < target_bytes {
            push_simple_let_line(&mut src, i);
            i += 1;
        }
        return src;
    }

    let mut src = String::with_capacity(lines.saturating_mul(18).saturating_add(64));
    for i in 0..lines {
        push_simple_let_line(&mut src, i);
    }
    src
}

fn push_simple_let_line(src: &mut String, i: usize) {
    src.push_str("let x");
    src.push_str(&i.to_string());
    src.push_str(" = ");
    src.push_str(&(i % 1024).to_string());
    src.push_str(";\n");
}

fn append_expected_print(expected_stdout: &mut String, value: i32) {
    expected_stdout.push_str(&value.to_string());
    expected_stdout.push('\n');
}

#[derive(Clone)]
struct GeneratedFunction {
    name: String,
    arity: usize,
    body: Option<Rc<GeneratedFunctionBody>>,
}

#[derive(Clone)]
enum GeneratedFunctionBody {
    Return(GeneratedExpr),
    LessBranch {
        left: GeneratedExpr,
        right: GeneratedExpr,
        then_expr: GeneratedExpr,
        else_expr: GeneratedExpr,
    },
}

#[derive(Clone)]
enum GeneratedExpr {
    Literal(i32),
    Param(usize),
    Add(Box<GeneratedExpr>, Box<GeneratedExpr>),
    Sub(Box<GeneratedExpr>, Box<GeneratedExpr>),
    Mul(Box<GeneratedExpr>, Box<GeneratedExpr>),
    Shl1(Box<GeneratedExpr>),
    BitAnd(Box<GeneratedExpr>, Box<GeneratedExpr>),
    BitOr(Box<GeneratedExpr>, Box<GeneratedExpr>),
    Call {
        function: GeneratedFunction,
        args: Vec<GeneratedExpr>,
    },
}

impl GeneratedFunction {
    fn source_call(&self, args: &[GeneratedExpr], params: &[String]) -> String {
        let mut out = String::new();
        out.push_str(&self.name);
        out.push('(');
        for (arg_i, arg) in args.iter().enumerate() {
            if arg_i != 0 {
                out.push_str(", ");
            }
            out.push_str(&arg.source(params));
        }
        out.push(')');
        out
    }

    fn eval(&self, args: &[i32]) -> i32 {
        assert_eq!(args.len(), self.arity, "generator oracle arity mismatch");
        match self
            .body
            .as_ref()
            .expect("generator oracle missing generated body")
            .as_ref()
        {
            GeneratedFunctionBody::Return(expr) => expr.eval(args),
            GeneratedFunctionBody::LessBranch {
                left,
                right,
                then_expr,
                else_expr,
            } => {
                if left.eval(args) < right.eval(args) {
                    then_expr.eval(args)
                } else {
                    else_expr.eval(args)
                }
            }
        }
    }
}

impl GeneratedExpr {
    fn binary_source(
        lhs: &GeneratedExpr,
        op: &str,
        rhs: &GeneratedExpr,
        params: &[String],
    ) -> String {
        format!("({} {op} {})", lhs.source(params), rhs.source(params))
    }

    fn source(&self, params: &[String]) -> String {
        match self {
            GeneratedExpr::Literal(value) => value.to_string(),
            GeneratedExpr::Param(index) => params[*index].clone(),
            GeneratedExpr::Add(lhs, rhs) => Self::binary_source(lhs, "+", rhs, params),
            GeneratedExpr::Sub(lhs, rhs) => Self::binary_source(lhs, "-", rhs, params),
            GeneratedExpr::Mul(lhs, rhs) => Self::binary_source(lhs, "*", rhs, params),
            GeneratedExpr::Shl1(expr) => format!("({} << 1)", expr.source(params)),
            GeneratedExpr::BitAnd(lhs, rhs) => Self::binary_source(lhs, "&", rhs, params),
            GeneratedExpr::BitOr(lhs, rhs) => Self::binary_source(lhs, "|", rhs, params),
            GeneratedExpr::Call { function, args } => function.source_call(args, params),
        }
    }

    fn eval(&self, params: &[i32]) -> i32 {
        match self {
            GeneratedExpr::Literal(value) => *value,
            GeneratedExpr::Param(index) => params[*index],
            GeneratedExpr::Add(lhs, rhs) => lhs.eval(params).wrapping_add(rhs.eval(params)),
            GeneratedExpr::Sub(lhs, rhs) => lhs.eval(params).wrapping_sub(rhs.eval(params)),
            GeneratedExpr::Mul(lhs, rhs) => lhs.eval(params).wrapping_mul(rhs.eval(params)),
            GeneratedExpr::Shl1(expr) => expr.eval(params).wrapping_shl(1),
            GeneratedExpr::BitAnd(lhs, rhs) => lhs.eval(params) & rhs.eval(params),
            GeneratedExpr::BitOr(lhs, rhs) => lhs.eval(params) | rhs.eval(params),
            GeneratedExpr::Call { function, args } => {
                let arg_values = args.iter().map(|arg| arg.eval(params)).collect::<Vec<_>>();
                function.eval(&arg_values)
            }
        }
    }
}

fn generated_add(lhs: GeneratedExpr, rhs: GeneratedExpr) -> GeneratedExpr {
    GeneratedExpr::Add(Box::new(lhs), Box::new(rhs))
}

fn generated_mul(lhs: GeneratedExpr, rhs: GeneratedExpr) -> GeneratedExpr {
    GeneratedExpr::Mul(Box::new(lhs), Box::new(rhs))
}

fn generated_sum(mut exprs: Vec<GeneratedExpr>) -> GeneratedExpr {
    let first = exprs.remove(0);
    exprs.into_iter().fold(first, generated_add)
}

fn generated_score_pair(left: GeneratedExpr, right: GeneratedExpr) -> GeneratedExpr {
    generated_add(generated_mul(left, GeneratedExpr::Literal(3)), right)
}

fn make_call_graph_source_artifact(
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    let mut functions = String::with_capacity(target_bytes.unwrap_or(lines.saturating_mul(64)));
    let mut main_body = String::with_capacity(lines.saturating_mul(24).min(64 * 1024));
    let mut rng = DeterministicRng::new(seed);
    let mut generated: Vec<GeneratedFunction> = Vec::new();
    let mut expected_stdout = String::new();
    let mut line_count = 3usize;
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
            push_call_graph_function(&mut functions, chunk, prior.as_ref(), &mut rng);
        line_count += function_lines;
        let call = generated_call_expr(&function, chunk + 7, &mut rng);
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

fn push_call_graph_function(
    src: &mut String,
    chunk: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunction, usize) {
    let arity = match chunk % 4 {
        0 => 0,
        1 => 1,
        2 => 2,
        _ => 3,
    };
    let name = varied_short_ident("f", chunk, rng);
    let params = call_graph_params(chunk, arity, rng);

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
    let (body, body_lines) = push_call_graph_function_body(src, chunk, arity, &params, prior, rng);
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

fn call_graph_params(chunk: usize, arity: usize, rng: &mut DeterministicRng) -> Vec<String> {
    (0..arity)
        .map(|param_i| {
            varied_short_ident("p", chunk.saturating_mul(4).saturating_add(param_i), rng)
        })
        .collect()
}

fn call_graph_return_generated_expr(
    chunk: usize,
    arity: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> GeneratedExpr {
    if let Some(prior) = prior
        && chunk % 5 == 4
    {
        let base = generated_call_expr(prior, chunk + 3, rng);
        return if arity == 0 {
            base
        } else {
            GeneratedExpr::Add(Box::new(base), Box::new(GeneratedExpr::Param(0)))
        };
    }

    match arity {
        0 => {
            let a = (rng.small_int() % 64) as i32;
            let b = (rng.small_int() % 64) as i32;
            GeneratedExpr::Add(
                Box::new(GeneratedExpr::Literal(a)),
                Box::new(GeneratedExpr::Literal(b)),
            )
        }
        1 => {
            let a = (rng.small_int() % 64) as i32;
            match chunk % 3 {
                0 => GeneratedExpr::Param(0),
                1 => GeneratedExpr::Add(
                    Box::new(GeneratedExpr::Param(0)),
                    Box::new(GeneratedExpr::Literal(a)),
                ),
                _ => GeneratedExpr::Add(
                    Box::new(GeneratedExpr::Shl1(Box::new(GeneratedExpr::Param(0)))),
                    Box::new(GeneratedExpr::Literal(a)),
                ),
            }
        }
        2 => match chunk % 3 {
            0 => GeneratedExpr::Add(
                Box::new(GeneratedExpr::Param(0)),
                Box::new(GeneratedExpr::Param(1)),
            ),
            1 => GeneratedExpr::Sub(
                Box::new(GeneratedExpr::Param(0)),
                Box::new(GeneratedExpr::Param(1)),
            ),
            _ => GeneratedExpr::Mul(
                Box::new(GeneratedExpr::Param(0)),
                Box::new(GeneratedExpr::Param(1)),
            ),
        },
        _ => match chunk % 3 {
            0 => GeneratedExpr::Sub(
                Box::new(GeneratedExpr::Add(
                    Box::new(GeneratedExpr::Param(0)),
                    Box::new(GeneratedExpr::Param(1)),
                )),
                Box::new(GeneratedExpr::Param(2)),
            ),
            1 => GeneratedExpr::BitOr(
                Box::new(GeneratedExpr::BitAnd(
                    Box::new(GeneratedExpr::Param(0)),
                    Box::new(GeneratedExpr::Param(1)),
                )),
                Box::new(GeneratedExpr::Param(2)),
            ),
            _ => GeneratedExpr::Sub(
                Box::new(GeneratedExpr::Add(
                    Box::new(GeneratedExpr::Param(0)),
                    Box::new(GeneratedExpr::Shl1(Box::new(GeneratedExpr::Param(1)))),
                )),
                Box::new(GeneratedExpr::Param(2)),
            ),
        },
    }
}

fn push_call_graph_function_body(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    if arity >= 2 && chunk % 11 == 5 {
        let then_expr = call_graph_return_generated_expr(chunk + 1, arity, prior, rng);
        let else_expr = call_graph_return_generated_expr(chunk + 2, arity, prior, rng);
        src.push_str("    if (");
        src.push_str(&params[0]);
        src.push_str(" < ");
        src.push_str(&params[1]);
        src.push_str(") {\n        return ");
        src.push_str(&then_expr.source(params));
        src.push_str(";\n    } else {\n        return ");
        src.push_str(&else_expr.source(params));
        src.push_str(";\n    }\n");
        return (
            GeneratedFunctionBody::LessBranch {
                left: GeneratedExpr::Param(0),
                right: GeneratedExpr::Param(1),
                then_expr,
                else_expr,
            },
            5,
        );
    }

    if arity >= 1 && chunk % 7 == 3 {
        let local = varied_short_ident("t", chunk, rng);
        let init = call_graph_return_generated_expr(chunk + 3, arity, prior, rng);
        let bump = (rng.small_int() % 9) as i32;
        src.push_str("    let ");
        src.push_str(&local);
        src.push_str(": i32 = ");
        src.push_str(&init.source(params));
        src.push_str(";\n    return ");
        src.push_str(&local);
        src.push_str(" + ");
        src.push_str(&bump.to_string());
        src.push_str(";\n");
        return (
            GeneratedFunctionBody::Return(GeneratedExpr::Add(
                Box::new(init),
                Box::new(GeneratedExpr::Literal(bump)),
            )),
            2,
        );
    }

    if arity >= 1 && chunk % 13 == 6 {
        let local = varied_short_ident("a", chunk, rng);
        let bump = (rng.small_int() % 7) as i32;
        src.push_str("    let ");
        src.push_str(&local);
        src.push_str(": i32 = ");
        src.push_str(&params[0]);
        src.push_str(";\n    ");
        src.push_str(&local);
        src.push_str(" += ");
        src.push_str(&bump.to_string());
        src.push_str(";\n    return ");
        src.push_str(&local);
        src.push_str(";\n");
        return (
            GeneratedFunctionBody::Return(GeneratedExpr::Add(
                Box::new(GeneratedExpr::Param(0)),
                Box::new(GeneratedExpr::Literal(bump)),
            )),
            3,
        );
    }

    let expr = call_graph_return_generated_expr(chunk, arity, prior, rng);
    src.push_str("    return ");
    src.push_str(&expr.source(params));
    src.push_str(";\n");
    (GeneratedFunctionBody::Return(expr), 1)
}

fn generated_call_expr(
    function: &GeneratedFunction,
    salt: usize,
    rng: &mut DeterministicRng,
) -> GeneratedExpr {
    let mut args = Vec::with_capacity(function.arity);
    for arg_i in 0..function.arity {
        let value = ((salt + arg_i) as u32).wrapping_add(rng.small_int()) % 64;
        let value_expr = GeneratedExpr::Literal(value as i32);
        if arg_i % 3 == 2 {
            let rhs = (rng.small_int() % 8) as i32;
            let factor = (rng.small_int() % 8 + 1) as i32;
            let offset = (rng.small_int() % 4) as i32;
            args.push(GeneratedExpr::Mul(
                Box::new(GeneratedExpr::Add(
                    Box::new(value_expr),
                    Box::new(GeneratedExpr::Literal(rhs)),
                )),
                Box::new(GeneratedExpr::Sub(
                    Box::new(GeneratedExpr::Literal(factor)),
                    Box::new(GeneratedExpr::Literal(offset)),
                )),
            ));
        } else if arg_i % 2 == 0 {
            args.push(value_expr);
        } else {
            let rhs = (rng.small_int() % 8) as i32;
            args.push(GeneratedExpr::Add(
                Box::new(value_expr),
                Box::new(GeneratedExpr::Literal(rhs)),
            ));
        }
    }
    GeneratedExpr::Call {
        function: function.clone(),
        args,
    }
}

fn make_expr_dense_source_artifact(
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    const EXPR_DENSE_PRINTS_PER_BLOCK: usize = 32;

    let mut functions = String::with_capacity(target_bytes.unwrap_or(lines.saturating_mul(96)));
    let mut main_body = String::with_capacity(lines.saturating_mul(32).min(96 * 1024));
    let mut print_functions = String::new();
    let mut print_block_body = String::new();
    let mut rng = DeterministicRng::new(seed ^ 0x0e95_dede_5eed);
    let mut generated = Vec::<GeneratedFunction>::new();
    let mut expected_stdout = String::new();
    let mut line_count = 3usize;
    let mut chunk = 0usize;
    let mut print_block_i = 0usize;
    let mut prints_in_block = 0usize;

    loop {
        let projected_len = functions
            .len()
            .saturating_add(print_functions.len())
            .saturating_add(print_block_body.len())
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
            push_expr_dense_function(&mut functions, chunk, prior.as_ref(), &mut rng);
        line_count += function_lines;

        let call = generated_call_expr(&function, chunk + 97, &mut rng);
        append_expected_print(&mut expected_stdout, call.eval(&[]));
        print_block_body.push_str("    print(");
        print_block_body.push_str(&call.source(&[]));
        print_block_body.push_str(");\n");
        line_count += 1;
        prints_in_block += 1;

        if prints_in_block == EXPR_DENSE_PRINTS_PER_BLOCK {
            line_count += flush_expr_dense_print_block(
                &mut print_functions,
                &mut main_body,
                &mut print_block_body,
                print_block_i,
            );
            print_block_i += 1;
            prints_in_block = 0;
        }

        generated.push(function);
        chunk += 1;
    }
    if !print_block_body.is_empty() {
        flush_expr_dense_print_block(
            &mut print_functions,
            &mut main_body,
            &mut print_block_body,
            print_block_i,
        );
    }

    let mut src = String::with_capacity(
        functions
            .len()
            .saturating_add(print_functions.len())
            .saturating_add(main_body.len())
            .saturating_add(32),
    );
    src.push_str(&functions);
    src.push_str(&print_functions);
    src.push_str("fn main() {\n");
    src.push_str(&main_body);
    src.push_str("    return 0;\n");
    src.push_str("}\n");
    SourceArtifact::single(src, Some(expected_stdout))
}

fn flush_expr_dense_print_block(
    print_functions: &mut String,
    main_body: &mut String,
    print_block_body: &mut String,
    block_i: usize,
) -> usize {
    if print_block_body.is_empty() {
        return 0;
    }

    print_functions.push_str("fn xd_print_block");
    print_functions.push_str(&block_i.to_string());
    print_functions.push_str("() -> i32 {\n");
    print_functions.push_str(print_block_body);
    print_functions.push_str("    return 0;\n}\n");
    print_block_body.clear();

    main_body.push_str("    let xd_print_result");
    main_body.push_str(&block_i.to_string());
    main_body.push_str(" = xd_print_block");
    main_body.push_str(&block_i.to_string());
    main_body.push_str("();\n");

    4
}

fn push_expr_dense_function(
    src: &mut String,
    chunk: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunction, usize) {
    let arity = 1 + rng.index(4);
    let name = varied_short_ident("xd", chunk, rng);
    let params = (0..arity)
        .map(|param_i| {
            varied_short_ident("xp", chunk.saturating_mul(8).saturating_add(param_i), rng)
        })
        .collect::<Vec<_>>();

    src.push_str("fn ");
    src.push_str(&name);
    src.push('(');
    for (param_i, param) in params.iter().enumerate() {
        if param_i != 0 {
            src.push_str(", ");
        }
        src.push_str(param);
        src.push_str(": i32");
    }
    src.push_str(") -> i32 {\n");

    let (body, body_lines) = if arity >= 2 && chunk % 5 == 2 {
        push_expr_dense_branch_body(src, chunk, arity, &params, prior, rng)
    } else if chunk % 4 == 1 {
        push_expr_dense_local_body(src, chunk, arity, &params, prior, rng)
    } else {
        let expr = expr_dense_generated_expr(chunk, 4, arity, prior, rng);
        src.push_str("    return ");
        src.push_str(&expr.source(&params));
        src.push_str(";\n");
        (GeneratedFunctionBody::Return(expr), 1)
    };
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

fn push_expr_dense_branch_body(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let left = expr_dense_generated_expr(chunk + 11, 2, arity, prior, rng);
    let right = expr_dense_generated_expr(chunk + 17, 2, arity, prior, rng);
    let then_expr = expr_dense_generated_expr(chunk + 23, 3, arity, prior, rng);
    let else_expr = expr_dense_generated_expr(chunk + 29, 3, arity, prior, rng);

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

fn push_expr_dense_local_body(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let local = varied_short_ident("xl", chunk, rng);
    let seed_expr = expr_dense_generated_expr(chunk + 31, 3, arity, prior, rng);
    let bump = ((rng.small_int() % 17) as i32) - 8;
    let return_expr = GeneratedExpr::Sub(
        Box::new(GeneratedExpr::Add(
            Box::new(seed_expr.clone()),
            Box::new(GeneratedExpr::Literal(bump)),
        )),
        Box::new(GeneratedExpr::Param(chunk % arity)),
    );

    src.push_str("    let ");
    src.push_str(&local);
    src.push_str(": i32 = ");
    src.push_str(&seed_expr.source(params));
    src.push_str(";\n    return (");
    src.push_str(&local);
    src.push_str(" + ");
    src.push_str(&bump.to_string());
    src.push_str(") - ");
    src.push_str(&params[chunk % arity]);
    src.push_str(";\n");

    (GeneratedFunctionBody::Return(return_expr), 2)
}

fn expr_dense_generated_expr(
    salt: usize,
    depth: usize,
    arity: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> GeneratedExpr {
    if depth == 0 {
        return expr_dense_leaf(salt, arity, rng);
    }

    if let Some(prior) = prior
        && salt % 7 == 3
    {
        return expr_dense_prior_call(prior, salt, depth, arity, rng);
    }

    match (rng.small_int() as usize + salt + depth) % 7 {
        0 => GeneratedExpr::Add(
            Box::new(expr_dense_generated_expr(
                salt + 1,
                depth - 1,
                arity,
                prior,
                rng,
            )),
            Box::new(expr_dense_generated_expr(
                salt + 9,
                depth - 1,
                arity,
                prior,
                rng,
            )),
        ),
        1 => GeneratedExpr::Sub(
            Box::new(expr_dense_generated_expr(
                salt + 1,
                depth - 1,
                arity,
                prior,
                rng,
            )),
            Box::new(expr_dense_generated_expr(
                salt + 9,
                depth - 1,
                arity,
                prior,
                rng,
            )),
        ),
        2 => GeneratedExpr::Mul(
            Box::new(expr_dense_generated_expr(
                salt + 1,
                depth - 1,
                arity,
                prior,
                rng,
            )),
            Box::new(expr_dense_generated_expr(
                salt + 9,
                depth - 1,
                arity,
                prior,
                rng,
            )),
        ),
        3 => GeneratedExpr::BitAnd(
            Box::new(expr_dense_generated_expr(
                salt + 1,
                depth - 1,
                arity,
                prior,
                rng,
            )),
            Box::new(expr_dense_generated_expr(
                salt + 9,
                depth - 1,
                arity,
                prior,
                rng,
            )),
        ),
        4 => GeneratedExpr::BitOr(
            Box::new(expr_dense_generated_expr(
                salt + 1,
                depth - 1,
                arity,
                prior,
                rng,
            )),
            Box::new(expr_dense_generated_expr(
                salt + 9,
                depth - 1,
                arity,
                prior,
                rng,
            )),
        ),
        5 => GeneratedExpr::Shl1(Box::new(expr_dense_generated_expr(
            salt + 1,
            depth - 1,
            arity,
            prior,
            rng,
        ))),
        _ => generated_add(
            expr_dense_generated_expr(salt + 5, depth - 1, arity, prior, rng),
            GeneratedExpr::Literal(((rng.small_int() % 19) as i32) - 9),
        ),
    }
}

fn expr_dense_leaf(salt: usize, arity: usize, rng: &mut DeterministicRng) -> GeneratedExpr {
    if arity != 0 && salt % 3 != 0 {
        GeneratedExpr::Param(salt % arity)
    } else {
        GeneratedExpr::Literal(((rng.small_int() % 31) as i32) - 15)
    }
}

fn expr_dense_prior_call(
    prior: &GeneratedFunction,
    salt: usize,
    depth: usize,
    arity: usize,
    rng: &mut DeterministicRng,
) -> GeneratedExpr {
    let args = (0..prior.arity)
        .map(|arg_i| {
            expr_dense_generated_expr(
                salt.saturating_add(arg_i).saturating_add(37),
                depth.saturating_sub(1).min(2),
                arity,
                None,
                rng,
            )
        })
        .collect::<Vec<_>>();
    GeneratedExpr::Call {
        function: prior.clone(),
        args,
    }
}

fn make_abi_call_source_artifact(
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    let mut functions = String::with_capacity(target_bytes.unwrap_or(lines.saturating_mul(76)));
    let mut main_body = String::with_capacity(lines.saturating_mul(28).min(96 * 1024));
    let mut rng = DeterministicRng::new(seed ^ 0xaba1_c011_5eed);
    let mut generated: Vec<GeneratedFunction> = Vec::new();
    let mut expected_stdout = String::new();
    let mut line_count = 3usize;
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
            push_abi_call_function(&mut functions, chunk, prior.as_ref(), &mut rng);
        line_count += function_lines;

        let call = generated_call_expr(&function, chunk + 31, &mut rng);
        let printed = if let Some(prior) = prior.as_ref()
            && chunk % 4 == 1
        {
            let prior_call = generated_call_expr(prior, chunk + 37, &mut rng);
            generated_add(call, prior_call)
        } else {
            call
        };
        expected_stdout.push_str(&printed.eval(&[]).to_string());
        expected_stdout.push('\n');
        main_body.push_str("    print(");
        main_body.push_str(&printed.source(&[]));
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

fn push_abi_call_function(
    src: &mut String,
    chunk: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunction, usize) {
    let arity = chunk % 5;
    let name = varied_short_ident("abi", chunk, rng);
    let params = abi_call_params(chunk, arity, rng);

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
    let (body, body_lines) = push_abi_call_function_body(src, chunk, arity, &params, prior, rng);
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

fn abi_call_params(chunk: usize, arity: usize, rng: &mut DeterministicRng) -> Vec<String> {
    (0..arity)
        .map(|param_i| {
            varied_short_ident("ap", chunk.saturating_mul(5).saturating_add(param_i), rng)
        })
        .collect()
}

fn push_abi_call_function_body(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    if arity >= 2 && chunk % 9 == 4 {
        let then_expr = abi_call_return_expr(chunk + 1, arity, prior, rng);
        let else_expr = abi_call_return_expr(chunk + 2, arity, prior, rng);
        src.push_str("    if (");
        src.push_str(&params[0]);
        src.push_str(" < ");
        src.push_str(&params[1]);
        src.push_str(") {\n        return ");
        src.push_str(&then_expr.source(params));
        src.push_str(";\n    } else {\n        return ");
        src.push_str(&else_expr.source(params));
        src.push_str(";\n    }\n");
        return (
            GeneratedFunctionBody::LessBranch {
                left: GeneratedExpr::Param(0),
                right: GeneratedExpr::Param(1),
                then_expr,
                else_expr,
            },
            5,
        );
    }

    if arity >= 3 && chunk % 7 == 2 {
        let local = varied_short_ident("al", chunk, rng);
        let expr = abi_call_return_expr(chunk + 3, arity, prior, rng);
        let bump = (rng.small_int() % 11) as i32;
        src.push_str("    let ");
        src.push_str(&local);
        src.push_str(": i32 = ");
        src.push_str(&expr.source(params));
        src.push_str(";\n    return ");
        src.push_str(&local);
        src.push_str(" + ");
        src.push_str(&bump.to_string());
        src.push_str(";\n");
        return (
            GeneratedFunctionBody::Return(generated_add(expr, GeneratedExpr::Literal(bump))),
            2,
        );
    }

    let expr = abi_call_return_expr(chunk, arity, prior, rng);
    src.push_str("    return ");
    src.push_str(&expr.source(params));
    src.push_str(";\n");
    (GeneratedFunctionBody::Return(expr), 1)
}

fn abi_call_return_expr(
    chunk: usize,
    arity: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> GeneratedExpr {
    if let Some(prior) = prior
        && chunk % 4 == 0
    {
        let prior_call = generated_call_expr(prior, chunk + 41, rng);
        return if arity == 0 {
            prior_call
        } else {
            generated_add(prior_call, GeneratedExpr::Param(0))
        };
    }

    match arity {
        0 => GeneratedExpr::Literal((rng.small_int() % 97) as i32),
        1 => generated_add(
            GeneratedExpr::Param(0),
            GeneratedExpr::Literal((chunk % 17) as i32),
        ),
        2 => GeneratedExpr::Sub(
            Box::new(generated_mul(
                GeneratedExpr::Param(0),
                GeneratedExpr::Literal(2),
            )),
            Box::new(GeneratedExpr::Param(1)),
        ),
        3 => generated_add(
            generated_mul(GeneratedExpr::Param(0), GeneratedExpr::Param(1)),
            GeneratedExpr::Param(2),
        ),
        _ => GeneratedExpr::Sub(
            Box::new(generated_add(
                GeneratedExpr::Param(0),
                GeneratedExpr::Param(1),
            )),
            Box::new(generated_mul(
                GeneratedExpr::Param(2),
                GeneratedExpr::Param(3),
            )),
        ),
    }
}

fn varied_short_ident(prefix: &str, salt: usize, rng: &mut DeterministicRng) -> String {
    format!("{prefix}{salt:x}_{:03x}", rng.next_u32() & 0xfff)
}

struct DeterministicRng {
    state: u64,
}

impl DeterministicRng {
    fn new(seed: u64) -> Self {
        Self { state: seed | 1 }
    }

    fn next_u32(&mut self) -> u32 {
        self.state = self
            .state
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1);
        (self.state >> 32) as u32
    }

    fn small_int(&mut self) -> u32 {
        self.next_u32() % 64
    }

    fn index(&mut self, len: usize) -> usize {
        (self.next_u32() as usize) % len
    }
}
