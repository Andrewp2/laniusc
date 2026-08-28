mod common;

use laniusc_compiler::{
    compiler::CompileError,
    lexer::{GpuLexer, Token, tables::TokenKind},
};

#[test]
fn gpu_lexer_matches_verified_canonical_contract_cases() {
    common::block_on_gpu_with_timeout("verified lexer canonical contract", async move {
        let lexer = GpuLexer::new().await.expect("create GPU lexer");

        assert_kinds(
            &lexer,
            "pub fn in let for return if else while break continue true false const enum extern import impl match module self struct trait type where",
            &[
                TokenKind::Pub,
                TokenKind::Fn,
                TokenKind::In,
                TokenKind::Let,
                TokenKind::For,
                TokenKind::Return,
                TokenKind::If,
                TokenKind::Else,
                TokenKind::While,
                TokenKind::Break,
                TokenKind::Continue,
                TokenKind::True,
                TokenKind::False,
                TokenKind::Const,
                TokenKind::Enum,
                TokenKind::Extern,
                TokenKind::Import,
                TokenKind::Impl,
                TokenKind::Match,
                TokenKind::Module,
                TokenKind::SelfValue,
                TokenKind::Struct,
                TokenKind::Trait,
                TokenKind::Type,
                TokenKind::Where,
            ],
        )
        .await;

        assert_tokens(
            &lexer,
            "let letter fn",
            &[
                (TokenKind::Let, 0, 3),
                (TokenKind::Ident, 4, 6),
                (TokenKind::Fn, 11, 2),
            ],
        )
        .await;

        assert_tokens(
            &lexer,
            "1..=2",
            &[
                (TokenKind::Int, 0, 1),
                (TokenKind::DotDotEqual, 1, 2),
                (TokenKind::Assign, 3, 1),
                (TokenKind::Int, 4, 1),
            ],
        )
        .await;

        assert_tokens(
            &lexer,
            "abc /*x*/ 12..34 //x\n\"ok\"",
            &[
                (TokenKind::Ident, 0, 3),
                (TokenKind::Int, 10, 2),
                (TokenKind::DotDot, 12, 2),
                (TokenKind::Int, 14, 2),
                (TokenKind::String, 21, 4),
            ],
        )
        .await;
    });
}

#[test]
fn gpu_lexer_reports_verified_first_failure_offsets() {
    common::block_on_gpu_with_timeout("verified lexer first failures", async move {
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        for (source, expected_offset) in [
            ("@", 0),
            ("0x", 2),
            ("0b", 2),
            ("0o", 2),
            ("1_", 2),
            ("0x1_", 4),
            ("1e", 2),
            ("1e+", 3),
            ("1.0_", 4),
            ("\"abc", 4),
            ("/*abc", 5),
            ("\"a\n", 2),
        ] {
            let error = lexer
                .lex(source)
                .await
                .expect_err("malformed source must not produce a token stream");
            let failure = error
                .downcast_ref::<laniusc_compiler::lexer::LexicalFailure>()
                .expect("GPU lexer should preserve the typed lexical failure");
            assert_eq!(failure.offset, expected_offset, "source: {source:?}");
        }
    });
}

#[test]
fn compiler_diagnostic_preserves_the_gpu_lexers_first_failure() {
    let error = common::type_check_source_with_timeout("0x")
        .expect_err("an incomplete hexadecimal literal must be rejected");
    let CompileError::Diagnostic(diagnostic) = error else {
        panic!("expected a structured compiler diagnostic, got {error:?}");
    };
    assert_eq!(diagnostic.code, "LNC0046");
    let label = diagnostic
        .primary_label
        .expect("the lexical diagnostic must identify its source position");
    assert_eq!(label.byte_start, Some(2));
    assert_eq!(label.byte_end, Some(2));
    assert_eq!(label.line, 1);
    assert_eq!(label.column, 3);
    assert_eq!(label.message, "token is incomplete at end of file");
}

async fn assert_kinds(lexer: &GpuLexer, source: &str, expected: &[TokenKind]) {
    let actual = lexer
        .lex(source)
        .await
        .expect("GPU lexer should accept case");
    assert_eq!(
        actual.iter().map(|token| token.kind).collect::<Vec<_>>(),
        expected,
        "source:\n{source}"
    );
}

async fn assert_tokens(lexer: &GpuLexer, source: &str, expected: &[(TokenKind, usize, usize)]) {
    let actual = lexer
        .lex(source)
        .await
        .expect("GPU lexer should accept case");
    assert_eq!(token_rows(&actual), expected, "source:\n{source}");
}

fn token_rows(tokens: &[Token]) -> Vec<(TokenKind, usize, usize)> {
    tokens
        .iter()
        .map(|token| (token.kind, token.start, token.len))
        .collect()
}
