mod common;

use laniusc_compiler::{
    dev::generator::gen_valid_program,
    lexer::driver::GpuLexer,
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
};
use proptest::{
    collection::vec,
    prelude::*,
    sample::select,
    test_runner::{Config, RngSeed, TestCaseError, TestRunner},
};
use rand::{SeedableRng, rngs::StdRng};

#[test]
fn resident_parser_accepts_seeded_and_proptest_generated_programs() {
    common::block_on_gpu_with_timeout("generated parser fuzz", async move {
        let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tables/parse_tables.bin"
        )))
        .expect("load precomputed parse tables");
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        let parser = GpuParser::new().await.expect("create GPU parser");

        for seed in [7_u64, 12_345, 2_026] {
            let mut rng = StdRng::seed_from_u64(seed);
            let source = gen_valid_program(&mut rng, 512);
            assert_resident_parse_accepts(&lexer, &parser, &tables, &source)
                .await
                .unwrap_or_else(|err| {
                    panic!(
                        "resident parser should accept rand-generated seed {seed}:\n{source}\n{err}"
                    )
                });
        }

        let strategy = lanius_program();
        let mut runner = TestRunner::new(Config {
            cases: 48,
            // This is a deterministic GPU integration corpus. Replaying up to
            // thousands of GPU parses to shrink a failure obscures the useful
            // semantic diagnostic and can exceed the test's outer timeout.
            max_shrink_iters: 0,
            failure_persistence: None,
            rng_seed: RngSeed::Fixed(0x4c41_4e49_5553),
            ..Config::default()
        });

        runner
            .run(&strategy, |source| {
                pollster::block_on(assert_resident_syntax_accepts(
                    &lexer, &parser, &tables, &source,
                ))
                .map_err(|err| {
                    TestCaseError::fail(format!(
                        "resident LL(1) parser rejected proptest-generated program:\n{source}\n{err}"
                    ))
                })
            })
            .expect("resident LL(1) parser should accept proptest-generated programs");
    });
}

#[test]
fn resident_parser_accepts_proptest_numeric_range_for_programs() {
    common::block_on_gpu_with_timeout("numeric range parser proptest", async move {
        let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tables/parse_tables.bin"
        )))
        .expect("load precomputed parse tables");
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        let parser = GpuParser::new().await.expect("create GPU parser");

        let strategy = numeric_range_program();
        let mut runner = TestRunner::new(Config {
            cases: 64,
            max_shrink_iters: 2_048,
            failure_persistence: None,
            ..Config::default()
        });

        runner
            .run(&strategy, |source| {
                pollster::block_on(assert_resident_syntax_accepts(
                    &lexer, &parser, &tables, &source,
                ))
                .map_err(|err| {
                    TestCaseError::fail(format!(
                        "resident parser syntax rejected proptest-generated numeric range program:\n{source}\n{err}"
                    ))
                })
            })
            .expect("resident parser should accept proptest-generated numeric range programs");
    });
}

async fn assert_resident_parse_accepts(
    lexer: &GpuLexer,
    parser: &GpuParser,
    tables: &PrecomputedParseTables,
    source: &str,
) -> Result<(), String> {
    let result = lexer
        .with_resident_tokens(source, |_, _, buffers| {
            parser.parse_resident_tokens(
                buffers.n,
                &buffers.tokens_out,
                &buffers.token_count,
                tables,
            )
        })
        .await
        .map_err(|err| format!("resident lex failed: {err:#}"))?
        .map_err(|err| format!("resident parse failed: {err:#}"))?;

    if !result.ll1.accepted {
        let cpu_oracle = semantic_rejection_diagnostic(lexer, parser, tables, source).await;
        return Err(format!(
            "{}\nCPU LL(1) oracle: {cpu_oracle:?}",
            result.ll1.rejection_message()
        ));
    }

    Ok(())
}

async fn assert_resident_syntax_accepts(
    lexer: &GpuLexer,
    parser: &GpuParser,
    tables: &PrecomputedParseTables,
    source: &str,
) -> Result<(), String> {
    let checked = lexer
        .with_resident_tokens(source, |_, _, buffers| {
            parser.with_checked_resident_parse_artifacts(
                buffers.n,
                &buffers.tokens_out,
                &buffers.token_count,
                tables,
                |_| Ok::<(), String>(()),
            )
        })
        .await
        .map_err(|err| format!("resident lex failed: {err:#}"))?;

    let consumed = match checked {
        Ok(consumed) => consumed,
        Err(err) => {
            let cpu_oracle = semantic_rejection_diagnostic(lexer, parser, tables, source).await;
            return Err(format!(
                "resident LL(1) parse failed: {err:#}\nCPU LL(1) oracle: {cpu_oracle:?}"
            ));
        }
    };
    if let Err(err) = consumed {
        let cpu_oracle = semantic_rejection_diagnostic(lexer, parser, tables, source).await;
        return Err(format!(
            "resident LL(1) consume failed: {err}\nCPU LL(1) oracle: {cpu_oracle:?}"
        ));
    }
    Ok(())
}

async fn semantic_rejection_diagnostic(
    lexer: &GpuLexer,
    parser: &GpuParser,
    tables: &PrecomputedParseTables,
    source: &str,
) -> Result<String, String> {
    let tokens = lexer
        .lex(source)
        .await
        .map_err(|err| format!("debug lex failed: {err:#}"))?;
    let raw: Vec<u32> = tokens.iter().map(|token| token.kind as u32).collect();
    parser
        .debug_semantic_token_kinds_for_raw_token_kinds(&raw, tables)
        .map(|semantic| {
            let replay = tables.test_cpu_ll1_production_stream(&semantic);
            let context = replay.as_ref().err().map(|error| {
                let start = error.pos.saturating_sub(20);
                let end = (error.pos + 4).min(semantic.len().saturating_sub(1));
                (start..=end)
                    .map(|parser_i| {
                        let raw = parser_i.checked_sub(1).and_then(|token_i| {
                            tokens.get(token_i).map(|token| {
                                let end = token.start.saturating_add(token.len);
                                let text = source
                                    .get(token.start..end)
                                    .unwrap_or("<invalid utf8 boundary>");
                                format!("{:?} {text:?}", token.kind)
                            })
                        });
                        format!("{parser_i}: semantic={} raw={raw:?}", semantic[parser_i])
                    })
                    .collect::<Vec<_>>()
            });
            format!("{replay:?}; context={context:#?}")
        })
        .map_err(|err| format!("semantic classification failed: {err:#}"))
}

fn lanius_program() -> impl Strategy<Value = String> {
    vec(function_body(), 1..=3).prop_map(|bodies| {
        let mut out = String::from(
            "module fuzz::case;\n\n\
             struct Pair { field0: i32, field1: i32 }\n\n",
        );
        for (i, body) in bodies.into_iter().enumerate() {
            out.push_str(&format!(
                "fn f{i}(p0: i32, p1: i32, flag: bool) -> i32 {{\n{body}    return p0;\n}}\n\n"
            ));
        }
        out
    })
}

fn function_body() -> impl Strategy<Value = String> {
    vec(stmt(2, false), 0..=5).prop_map(|stmts| stmts.concat())
}

fn stmt(depth: u32, in_loop: bool) -> BoxedStrategy<String> {
    let simple = if in_loop {
        prop_oneof![
            let_stmt(),
            expr(3).prop_map(|expr| format!("    {expr};\n")),
            Just(String::from("    return p0;\n")),
            Just(String::from("    break;\n")),
            Just(String::from("    continue;\n")),
        ]
        .boxed()
    } else {
        prop_oneof![
            let_stmt(),
            expr(3).prop_map(|expr| format!("    {expr};\n")),
            Just(String::from("    return p0;\n")),
        ]
        .boxed()
    };

    if depth == 0 {
        return simple;
    }

    let nested = vec(stmt(depth - 1, in_loop), 0..=3);
    let loop_nested = vec(stmt(depth - 1, true), 0..=3);
    prop_oneof![
        5 => simple,
        2 => (condition_expr(2), nested.clone(), nested.clone()).prop_map(|(cond, then_stmts, else_stmts)| {
            format!(
                "    if ({cond}) {{\n{}    }}\n    else {{\n{}    }}\n",
                indent_block(&then_stmts.concat()),
                indent_block(&else_stmts.concat())
            )
        }),
        2 => (condition_expr(2), loop_nested.clone()).prop_map(|(cond, body)| {
            format!(
                "    while ({cond}) {{\n{}    }}\n",
                indent_block(&body.concat())
            )
        }),
        2 => (for_iterable(), loop_nested).prop_map(|(iterable, body)| {
            format!(
                "    for item in {iterable} {{\n{}    }}\n",
                indent_block(&body.concat())
            )
        }),
        1 => nested.prop_map(|body| {
            format!("    {{\n{}    }}\n", indent_block(&body.concat()))
        }),
    ]
    .boxed()
}

fn for_iterable() -> BoxedStrategy<String> {
    prop_oneof![
        3 => path_iterable(),
        2 => numeric_range_iterable(),
    ]
    .boxed()
}

fn path_iterable() -> BoxedStrategy<String> {
    select(vec!["iter::items", "items", "values"])
        .prop_map(String::from)
        .boxed()
}

fn numeric_range_program() -> impl Strategy<Value = String> {
    vec(numeric_range_for_stmt(), 1..=6).prop_map(|stmts| {
        format!(
            "module fuzz::ranges;\n\n\
             struct Pair {{ field0: i32, field1: i32 }}\n\n\
             fn f0(p0: i32, p1: i32, value: Pair) -> i32 {{\n{}    return p0;\n}}\n",
            stmts.concat()
        )
    })
}

fn numeric_range_for_stmt() -> impl Strategy<Value = String> {
    (var_name(), numeric_range_iterable()).prop_map(|(binding, iterable)| {
        format!("    for {binding} in {iterable} {{\n        let sink: i32 = {binding};\n    }}\n")
    })
}

fn numeric_range_iterable() -> BoxedStrategy<String> {
    prop_oneof![
        (
            0_u32..=255,
            small_gap(),
            small_gap(),
            prop::option::of(range_bound())
        )
            .prop_map(|(start, before, after, end)| {
                format!("{start}{before}..{after}{}", end.unwrap_or_default())
            }),
        (0_u32..=255, small_gap(), small_gap(), range_bound())
            .prop_map(|(start, before, after, end)| { format!("{start}{before}..={after}{end}") }),
        (small_gap(), prop::option::of(range_bound()))
            .prop_map(|(after, end)| format!("..{after}{}", end.unwrap_or_default())),
        (small_gap(), range_bound()).prop_map(|(after, end)| format!("..={after}{end}")),
    ]
    .boxed()
}

fn range_bound() -> BoxedStrategy<String> {
    let name = select(vec!["p0", "p1", "value", "item", "limit"]).prop_map(String::from);
    prop_oneof![(0_u32..=255).prop_map(|value| value.to_string()), name,].boxed()
}

fn small_gap() -> impl Strategy<Value = &'static str> {
    select(vec!["", " ", "\t"])
}

fn let_stmt() -> impl Strategy<Value = String> {
    (
        var_name(),
        prop::option::of(type_expr()),
        prop::option::of(expr(2)),
    )
        .prop_map(|(name, ty, init)| {
            let ty = ty.map(|ty| format!(": {ty}")).unwrap_or_default();
            let init = init.map(|expr| format!(" = {expr}")).unwrap_or_default();
            format!("    let {name}{ty}{init};\n")
        })
}

fn expr(depth: u32) -> BoxedStrategy<String> {
    expr_with_braced_literals(depth)
}

fn condition_expr(depth: u32) -> BoxedStrategy<String> {
    expr_with_braced_literals(depth)
}

fn expr_with_braced_literals(_depth: u32) -> BoxedStrategy<String> {
    let leaf = prop_oneof![
        select(vec!["p0", "p1", "flag", "value", "value::nested"])
            .prop_map(|name| name.to_string()),
        (0_i32..=255).prop_map(|value| value.to_string()),
        select(vec![
            "true", "false", "\"text\"", "\"\"", "'a'", "'\\n'", "0.0", "1.5", "10e2"
        ])
        .prop_map(|literal| literal.to_string()),
    ];

    leaf.prop_recursive(3, 64, 4, move |inner| {
        let op = select(vec![
            "||", "&&", "|", "^", "&", "==", "!=", "<", ">", "<=", ">=", "<<", ">>", "+", "-", "*",
            "/", "%",
        ]);
        let common = prop_oneof![
            inner.clone().prop_map(|expr| format!("({expr})")),
            // Keep recursively nested unary minuses from maximal-munching into
            // the decrement token.
            inner.clone().prop_map(|expr| format!("- {expr}")),
            inner.clone().prop_map(|expr| format!("!{expr}")),
            (inner.clone(), op, inner.clone())
                .prop_map(|(left, op, right)| { format!("{left} {op} {right}") }),
            (inner.clone(), vec(inner.clone(), 0..=2))
                .prop_map(|(callee, args)| { format!("{callee}({})", args.join(", ")) }),
            (inner.clone(), inner.clone()).prop_map(|(base, index)| { format!("{base}[{index}]") }),
            inner.clone().prop_map(|base| format!("({base}).field0")),
            vec(inner.clone(), 0..=3).prop_map(|elems| { format!("[{}]", elems.join(", ")) }),
        ]
        .boxed();

        prop_oneof![
            common,
            (inner.clone(), inner.clone()).prop_map(|(field0, field1)| {
                format!("Pair {{ field0: {field0}, field1: {field1} }}")
            }),
        ]
    })
    .boxed()
}

fn type_expr() -> BoxedStrategy<String> {
    let leaf = select(vec!["i32", "bool", "u32", "usize", "Pair"]).prop_map(|ty| ty.to_string());
    leaf.prop_recursive(2, 24, 2, |inner| {
        prop_oneof![
            // Keep recursively nested reference tokens lexically distinct from
            // the expression-level `&&` token produced by maximal munch.
            inner.clone().prop_map(|ty| format!("& {ty}")),
            inner.clone().prop_map(|ty| format!("[{ty}]")),
            (inner.clone(), 0_u32..=8).prop_map(|(ty, len)| format!("[{ty}; {len}]")),
        ]
    })
    .boxed()
}

fn var_name() -> impl Strategy<Value = String> {
    (0_u32..=8).prop_map(|i| format!("v{i}"))
}

fn indent_block(source: &str) -> String {
    source.lines().map(|line| format!("    {line}\n")).collect()
}
