use laniusc::lexer::{gpu::driver::GpuLexer, tables::tokens::TokenKind};

#[test]
fn gpu_lexer_retags_local_syntax_context() {
    use TokenKind::*;

    pollster::block_on(async {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer
            .lex("-a + +b - c f(a)[b] + [c] + (d)")
            .await
            .expect("lex");
        let kinds = tokens
            .into_iter()
            .map(|token| token.kind)
            .collect::<Vec<_>>();

        assert_eq!(
            kinds,
            vec![
                PrefixMinus,
                Ident,
                InfixPlus,
                PrefixPlus,
                Ident,
                InfixMinus,
                Ident,
                Ident,
                CallLParen,
                Ident,
                CallRParen,
                IndexLBracket,
                Ident,
                IndexRBracket,
                InfixPlus,
                ArrayLBracket,
                Ident,
                ArrayRBracket,
                InfixPlus,
                GroupLParen,
                Ident,
                GroupRParen,
            ]
        );
    });
}

#[test]
fn gpu_lexer_retags_keywords() {
    use TokenKind::*;

    pollster::block_on(async {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer
            .lex("pub fn f() -> i32 { let x = 1; if (x) { return x; } else { while (x) { break; continue; } } }")
            .await
            .expect("lex");
        let kinds = tokens
            .into_iter()
            .map(|token| token.kind)
            .collect::<Vec<_>>();

        assert_eq!(
            kinds,
            vec![
                Pub,
                Fn,
                Ident,
                CallLParen,
                CallRParen,
                Arrow,
                Ident,
                LBrace,
                Let,
                Ident,
                Assign,
                Int,
                Semicolon,
                If,
                GroupLParen,
                Ident,
                GroupRParen,
                LBrace,
                Return,
                Ident,
                Semicolon,
                RBrace,
                Else,
                LBrace,
                While,
                GroupLParen,
                Ident,
                GroupRParen,
                LBrace,
                Break,
                Semicolon,
                Continue,
                Semicolon,
                RBrace,
                RBrace,
                RBrace,
            ]
        );
    });
}
