use laniusc::lexer::{cpu::lex_on_cpu, gpu::driver::GpuLexer, tables::tokens::TokenKind};

#[test]
fn cpu_lexer_retags_bool_keywords() {
    use TokenKind::*;

    let kinds = lex_on_cpu("let t = true; let f = false;")
        .expect("CPU lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Let, LetIdent, LetAssign, True, Semicolon, Let, LetIdent, LetAssign, False, Semicolon,
        ]
    );
}

#[test]
fn cpu_lexer_retags_const_keyword() {
    use TokenKind::*;

    let kinds = lex_on_cpu("const LIMIT: i32 = 7;")
        .expect("CPU lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![Const, Ident, Colon, TypeIdent, Assign, Int, Semicolon]
    );
}

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
            .lex("const LIMIT: i32 = 7; pub fn f() -> i32 { let x = 1; let t = true; let f = false; if (x) { return x; } else { while (x) { break; continue; } } }")
            .await
            .expect("lex");
        let kinds = tokens
            .into_iter()
            .map(|token| token.kind)
            .collect::<Vec<_>>();

        assert_eq!(
            kinds,
            vec![
                Const, Ident, Colon, Ident, Assign, Int, Semicolon, Pub, Fn, Ident, LParen, RParen,
                Arrow, Ident, LBrace, Let, Ident, Assign, Int, Semicolon, Let, Ident, Assign, True,
                Semicolon, Let, Ident, Assign, False, Semicolon, If, LParen, Ident, RParen, LBrace,
                Return, Ident, Semicolon, RBrace, Else, LBrace, While, LParen, Ident, RParen,
                LBrace, Break, Semicolon, Continue, Semicolon, RBrace, RBrace, RBrace,
            ]
        );
    });
}
