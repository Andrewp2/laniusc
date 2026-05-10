mod common;

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
fn cpu_lexer_retags_enum_keyword() {
    use TokenKind::*;

    let kinds = lex_on_cpu("enum Ordering { Less, Equal, Greater }")
        .expect("CPU lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Enum, Ident, LBrace, Ident, Comma, Ident, Comma, Ident, RBrace
        ]
    );
}

#[test]
fn cpu_lexer_retags_struct_keyword() {
    use TokenKind::*;

    let kinds = lex_on_cpu("struct VecHeader { len: i32 }")
        .expect("CPU lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![Struct, Ident, LBrace, Ident, Colon, TypeIdent, RBrace]
    );
}

#[test]
fn cpu_lexer_retags_impl_keyword() {
    use TokenKind::*;

    let kinds = lex_on_cpu("impl VecHeader { pub fn len() -> i32 { return 0; } }")
        .expect("CPU lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Impl,
            Ident,
            LBrace,
            Pub,
            Fn,
            Ident,
            ParamLParen,
            ParamRParen,
            Arrow,
            TypeIdent,
            LBrace,
            Return,
            Int,
            Semicolon,
            RBrace,
            RBrace,
        ]
    );
}

#[test]
fn cpu_lexer_retags_trait_keyword() {
    use TokenKind::*;

    let kinds = lex_on_cpu("trait Eq<T> { fn eq(left: T, right: T) -> bool; }")
        .expect("CPU lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Trait,
            Ident,
            Lt,
            Ident,
            Gt,
            LBrace,
            Fn,
            Ident,
            ParamLParen,
            ParamIdent,
            Colon,
            TypeIdent,
            ParamComma,
            ParamIdent,
            Colon,
            TypeIdent,
            ParamRParen,
            Arrow,
            TypeIdent,
            Semicolon,
            RBrace,
        ]
    );
}

#[test]
fn cpu_lexer_splits_nested_generic_closers_in_type_contexts() {
    use TokenKind::*;

    let kinds =
        lex_on_cpu("fn same<T: Eq<T>>(left: T, right: T) -> bool { return left.eq(right); }")
            .expect("CPU lex")
            .into_iter()
            .map(|token| token.kind)
            .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Fn,
            Ident,
            Lt,
            Ident,
            Colon,
            TypeIdent,
            Lt,
            Ident,
            Gt,
            Gt,
            GroupLParen,
            Ident,
            Colon,
            TypeIdent,
            Comma,
            Ident,
            Colon,
            TypeIdent,
            GroupRParen,
            Arrow,
            TypeIdent,
            LBrace,
            Return,
            Ident,
            Dot,
            Ident,
            CallLParen,
            Ident,
            CallRParen,
            Semicolon,
            RBrace,
        ]
    );
}

#[test]
fn cpu_lexer_splits_nested_generic_closers_after_multiple_bounds() {
    use TokenKind::*;

    let kinds = lex_on_cpu("fn key<T: Eq<T> + Hash<T>>(value: T) -> u32 { return value.hash(); }")
        .expect("CPU lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Fn,
            Ident,
            Lt,
            Ident,
            Colon,
            TypeIdent,
            Lt,
            Ident,
            Gt,
            PrefixPlus,
            Ident,
            Lt,
            Ident,
            Gt,
            Gt,
            GroupLParen,
            Ident,
            Colon,
            TypeIdent,
            GroupRParen,
            Arrow,
            TypeIdent,
            LBrace,
            Return,
            Ident,
            Dot,
            Ident,
            CallLParen,
            CallRParen,
            Semicolon,
            RBrace,
        ]
    );
}

#[test]
fn cpu_lexer_retags_for_in_keywords() {
    use TokenKind::*;

    let kinds = lex_on_cpu("for item in values { continue; }")
        .expect("CPU lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![For, Ident, In, Ident, LBrace, Continue, Semicolon, RBrace]
    );
}

#[test]
fn cpu_lexer_retags_extern_keyword() {
    use TokenKind::*;

    let kinds = lex_on_cpu(r#"pub extern "wasm" fn host_alloc(size: usize) -> u32;"#)
        .expect("CPU lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Pub,
            Extern,
            String,
            Fn,
            Ident,
            ParamLParen,
            ParamIdent,
            Colon,
            TypeIdent,
            ParamRParen,
            Arrow,
            TypeIdent,
            Semicolon,
        ]
    );
}

#[test]
fn cpu_lexer_retags_type_keyword() {
    use TokenKind::*;

    let kinds = lex_on_cpu("pub type Count = i32;")
        .expect("CPU lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(kinds, vec![Pub, Type, Ident, Assign, Ident, Semicolon]);
}

#[test]
fn cpu_lexer_retags_match_keyword() {
    use TokenKind::*;

    let kinds = lex_on_cpu("match (value) { _ -> value }")
        .expect("CPU lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Match,
            GroupLParen,
            Ident,
            GroupRParen,
            LBrace,
            Ident,
            Arrow,
            TypeIdent,
            RBrace,
        ]
    );
}

#[test]
fn cpu_lexer_retags_module_and_import_keywords() {
    use TokenKind::*;

    let kinds = lex_on_cpu("module core::i32; import core::bool; import \"stdlib/i32.lani\";")
        .expect("CPU lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Module, Ident, Colon, Colon, TypeIdent, Semicolon, Import, Ident, Colon, Colon,
            TypeIdent, Semicolon, Import, String, Semicolon,
        ]
    );
}

#[test]
fn gpu_lexer_emits_raw_local_syntax_tokens() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU lexer local syntax tokens", async move {
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

    common::block_on_gpu_with_timeout("GPU lexer keyword retagging", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer
            .lex("module core::i32; import core::bool; import \"stdlib/i32.lani\"; extern \"wasm\" fn host_alloc(size: usize) -> u32; type Count = i32; struct VecHeader { len: i32 } impl VecHeader { fn len() -> i32 { return 0; } } trait Eq { fn eq(left: i32, right: i32) -> bool; } enum Ordering { Less, Equal, Greater } const LIMIT: i32 = 7; pub fn f() -> i32 { let x = 1; let t = true; let f = false; let m = match (x) { _ -> x }; for item in values { continue; } if (x) { return x; } else { while (x) { break; continue; } } }")
            .await
            .expect("lex");
        let kinds = tokens
            .into_iter()
            .map(|token| token.kind)
            .collect::<Vec<_>>();

        assert_eq!(
            kinds,
            vec![
                Module, Ident, Colon, Colon, Ident, Semicolon, Import, Ident, Colon, Colon, Ident,
                Semicolon, Import, String, Semicolon, Extern, String, Fn, Ident, LParen, Ident,
                Colon, Ident, RParen, Arrow, Ident, Semicolon, Type, Ident, Assign, Ident,
                Semicolon, Struct, Ident, LBrace, Ident, Colon, Ident, RBrace, Impl, Ident, LBrace,
                Fn, Ident, LParen, RParen, Arrow, Ident, LBrace, Return, Int, Semicolon, RBrace,
                RBrace, Trait, Ident, LBrace, Fn, Ident, LParen, Ident, Colon, Ident, Comma, Ident,
                Colon, Ident, RParen, Arrow, Ident, Semicolon, RBrace, Enum, Ident, LBrace, Ident,
                Comma, Ident, Comma, Ident, RBrace, Const, Ident, Colon, Ident, Assign, Int,
                Semicolon, Pub, Fn, Ident, LParen, RParen, Arrow, Ident, LBrace, Let, Ident,
                Assign, Int, Semicolon, Let, Ident, Assign, True, Semicolon, Let, Ident, Assign,
                False, Semicolon, Let, Ident, Assign, Match, LParen, Ident, RParen, LBrace, Ident,
                Arrow, Ident, RBrace, Semicolon, For, Ident, In, Ident, LBrace, Continue,
                Semicolon, RBrace, If, LParen, Ident, RParen, LBrace, Return, Ident, Semicolon,
                RBrace, Else, LBrace, While, LParen, Ident, RParen, LBrace, Break, Semicolon,
                Continue, Semicolon, RBrace, RBrace, RBrace,
            ]
        );
    });
}
