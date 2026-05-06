use laniusc::lexer::{gpu::driver::GpuLexer, tables::tokens::TokenKind};

#[test]
fn gpu_lexer_emits_raw_local_syntax_tokens() {
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
                Minus, Ident, Plus, Plus, Ident, Minus, Ident, Ident, LParen, Ident, RParen,
                LBracket, Ident, RBracket, Plus, LBracket, Ident, RBracket, Plus, LParen, Ident,
                RParen,
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
                Pub, Fn, Ident, LParen, RParen, Arrow, Ident, LBrace, Let, Ident, Assign, Int,
                Semicolon, If, LParen, Ident, RParen, LBrace, Return, Ident, Semicolon, RBrace,
                Else, LBrace, While, LParen, Ident, RParen, LBrace, Break, Semicolon, Continue,
                Semicolon, RBrace, RBrace, RBrace,
            ]
        );
    });
}
