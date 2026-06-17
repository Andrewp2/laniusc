mod common;

use laniusc_compiler::lexer::{
    GpuLexer,
    Token,
    tables::TokenKind,
    test_cpu::{TestCpuToken, lex_on_test_cpu},
};
use proptest::{
    collection::vec,
    prelude::*,
    sample::select,
    test_runner::{Config, TestCaseError, TestRunner},
};

#[test]
fn lexer_tokenizes_known_dot_frontiers() {
    common::block_on_gpu_with_timeout("lexer dot frontier examples", async move {
        let lexer = GpuLexer::new().await.expect("create GPU lexer");

        for (source, expected) in [
            (
                "point.x",
                vec![
                    (TokenKind::Ident, "point"),
                    (TokenKind::Dot, "."),
                    (TokenKind::Ident, "x"),
                ],
            ),
            (
                "a..b",
                vec![
                    (TokenKind::Ident, "a"),
                    (TokenKind::DotDot, ".."),
                    (TokenKind::Ident, "b"),
                ],
            ),
            (
                "0..samples",
                vec![
                    (TokenKind::Int, "0"),
                    (TokenKind::DotDot, ".."),
                    (TokenKind::Ident, "samples"),
                ],
            ),
            (
                "1.0..n",
                vec![
                    (TokenKind::Float, "1.0"),
                    (TokenKind::DotDot, ".."),
                    (TokenKind::Ident, "n"),
                ],
            ),
            (
                ".5..n",
                vec![
                    (TokenKind::Float, ".5"),
                    (TokenKind::DotDot, ".."),
                    (TokenKind::Ident, "n"),
                ],
            ),
            (
                "1..=end",
                vec![
                    (TokenKind::Int, "1"),
                    (TokenKind::DotDotEqual, ".."),
                    (TokenKind::Assign, "="),
                    (TokenKind::Ident, "end"),
                ],
            ),
            (
                "for i in 0..n {}",
                vec![
                    (TokenKind::For, "for"),
                    (TokenKind::Ident, "i"),
                    (TokenKind::In, "in"),
                    (TokenKind::Int, "0"),
                    (TokenKind::DotDot, ".."),
                    (TokenKind::Ident, "n"),
                    (TokenKind::LBrace, "{"),
                    (TokenKind::RBrace, "}"),
                ],
            ),
        ] {
            assert_expected_tokens(&lexer, source, &expected).await;
        }
    });
}

#[test]
fn lexer_dot_frontier_property_matches_cpu_oracle() {
    common::block_on_gpu_with_timeout("lexer dot frontier property", async move {
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        let strategy = dot_frontier_source();
        let mut runner = TestRunner::new(Config {
            cases: 128,
            max_shrink_iters: 2_048,
            failure_persistence: None,
            ..Config::default()
        });

        runner
            .run(&strategy, |source| {
                let cpu = lex_on_test_cpu(&source).map_err(|err| {
                    TestCaseError::fail(format!(
                        "test CPU lexer rejected generated frontier source:\n{source}\n{err}"
                    ))
                })?;
                let gpu = pollster::block_on(lexer.lex(&source)).map_err(|err| {
                    TestCaseError::fail(format!(
                        "GPU lexer rejected generated frontier source:\n{source}\n{err:#}"
                    ))
                })?;

                prop_assert_eq!(
                    gpu_stream(&gpu),
                    test_cpu_stream(&cpu),
                    "source:\n{}",
                    source
                );
                Ok(())
            })
            .expect("dot frontier property should match the test CPU oracle");
    });
}

async fn assert_expected_tokens(lexer: &GpuLexer, source: &str, expected: &[(TokenKind, &str)]) {
    let cpu = lex_on_test_cpu(source).expect("test CPU lexer should accept exact frontier case");
    let gpu = lexer
        .lex(source)
        .await
        .expect("GPU lexer should accept exact frontier case");
    assert_eq!(gpu_stream(&gpu), test_cpu_stream(&cpu), "source:\n{source}");

    let actual = token_texts(source, &gpu);
    let expected = expected
        .iter()
        .map(|(kind, text)| (*kind, (*text).to_string()))
        .collect::<Vec<_>>();
    assert_eq!(actual, expected, "source:\n{source}");
}

fn dot_frontier_source() -> impl Strategy<Value = String> {
    vec(dot_frontier_line(), 1..=32).prop_map(|lines| lines.concat())
}

fn dot_frontier_line() -> impl Strategy<Value = String> {
    (
        dot_frontier_left(),
        small_gap(),
        dot_frontier_separator(),
        small_gap(),
        dot_frontier_right(),
    )
        .prop_map(|(left, before, sep, after, right)| {
            format!("{left}{before}{sep}{after}{right}\n")
        })
}

fn dot_frontier_left() -> impl Strategy<Value = &'static str> {
    select(vec![
        "", "a", "point", "point.x", "call()", "arr[0]", "0", "1", "12", "1.", "1.0", "10.25", ".5",
    ])
}

fn dot_frontier_separator() -> impl Strategy<Value = &'static str> {
    select(vec![".", "..", "...", "....", "..=", ".=", ". ."])
}

fn dot_frontier_right() -> impl Strategy<Value = &'static str> {
    select(vec![
        "", "b", "b.c", "0", "2", ".5", "tail()", "items[1]", "{}", "(x)",
    ])
}

fn small_gap() -> impl Strategy<Value = &'static str> {
    select(vec!["", " ", "\t", "\n"])
}

fn gpu_stream(tokens: &[Token]) -> Vec<(TokenKind, usize, usize)> {
    tokens
        .iter()
        .map(|token| (token.kind, token.start, token.len))
        .collect()
}

fn test_cpu_stream(tokens: &[TestCpuToken]) -> Vec<(TokenKind, usize, usize)> {
    tokens
        .iter()
        .map(|token| (token.kind, token.start, token.len))
        .collect()
}

fn token_texts(source: &str, tokens: &[Token]) -> Vec<(TokenKind, String)> {
    tokens
        .iter()
        .map(|token| {
            let start = token.start;
            let end = start + token.len;
            (token.kind, source[start..end].to_string())
        })
        .collect()
}
