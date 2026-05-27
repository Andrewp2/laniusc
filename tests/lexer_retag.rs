mod common;

use laniusc::{
    lexer::{driver::GpuLexer, tables::tokens::TokenKind, test_cpu::lex_on_test_cpu},
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
};

fn normalized_reuse_kind(kind: TokenKind) -> TokenKind {
    match kind {
        TokenKind::LetIdent
        | TokenKind::ParamIdent
        | TokenKind::TypeIdent
        | TokenKind::TypeAliasNameIdent
        | TokenKind::TraitNameIdent
        | TokenKind::GenericParamIdent
        | TokenKind::WhereIdent
        | TokenKind::BoundTypeIdent => TokenKind::Ident,
        TokenKind::MemberIdent => TokenKind::Ident,
        TokenKind::LetAssign
        | TokenKind::DeclAssign
        | TokenKind::TypeAliasAssign
        | TokenKind::ConstAssign => TokenKind::Assign,
        TokenKind::ArgComma
        | TokenKind::ArrayComma
        | TokenKind::ParamComma
        | TokenKind::TypeArgComma
        | TokenKind::GenericParamComma
        | TokenKind::EnumFieldComma
        | TokenKind::MatchArmComma
        | TokenKind::PatternComma
        | TokenKind::WhereComma
        | TokenKind::EnumVariantComma
        | TokenKind::StructFieldComma
        | TokenKind::StructLitComma
        | TokenKind::BoundTypeArgComma => TokenKind::Comma,
        TokenKind::BoundColon | TokenKind::TypeColon | TokenKind::PathColon => TokenKind::Colon,
        TokenKind::TypeArrayLBracket => TokenKind::LBracket,
        TokenKind::TypeArrayRBracket => TokenKind::RBracket,
        TokenKind::TypeSemicolon
        | TokenKind::TraitMethodSemicolon
        | TokenKind::ImportSemicolon
        | TokenKind::ModuleSemicolon
        | TokenKind::ExternSemicolon
        | TokenKind::TypeAliasSemicolon
        | TokenKind::ConstSemicolon
        | TokenKind::LetSemicolon
        | TokenKind::ReturnSemicolon
        | TokenKind::ExprSemicolon
        | TokenKind::BreakSemicolon
        | TokenKind::ContinueSemicolon => TokenKind::Semicolon,
        TokenKind::IfLBrace
        | TokenKind::MatchLBrace
        | TokenKind::ImplLBrace
        | TokenKind::TraitLBrace
        | TokenKind::StructLitLBrace
        | TokenKind::StructDeclLBrace
        | TokenKind::EnumLBrace
        | TokenKind::FnBlockLBrace
        | TokenKind::ImplFnBlockLBrace => TokenKind::LBrace,
        TokenKind::IfRBrace
        | TokenKind::MatchRBrace
        | TokenKind::ImplRBrace
        | TokenKind::TraitRBrace
        | TokenKind::StructLitRBrace
        | TokenKind::StructDeclRBrace
        | TokenKind::EnumRBrace
        | TokenKind::FnBlockRBrace
        | TokenKind::ImplFnBlockRBrace => TokenKind::RBrace,
        TokenKind::ParamLParen
        | TokenKind::CallLParen
        | TokenKind::GroupLParen
        | TokenKind::PatternLParen
        | TokenKind::EnumPayloadLParen => TokenKind::LParen,
        TokenKind::ParamRParen
        | TokenKind::CallRParen
        | TokenKind::GroupRParen
        | TokenKind::PatternRParen
        | TokenKind::EnumPayloadRParen => TokenKind::RParen,
        TokenKind::ArrayLBracket | TokenKind::IndexLBracket => TokenKind::LBracket,
        TokenKind::ArrayRBracket | TokenKind::IndexRBracket => TokenKind::RBracket,
        TokenKind::PrefixPlus | TokenKind::InfixPlus | TokenKind::BoundPlus => TokenKind::Plus,
        TokenKind::PrefixMinus | TokenKind::InfixMinus => TokenKind::Minus,
        TokenKind::PrefixInc | TokenKind::PostfixInc => TokenKind::Inc,
        TokenKind::PrefixDec | TokenKind::PostfixDec => TokenKind::Dec,
        TokenKind::TypeArgLt | TokenKind::GenericParamLt | TokenKind::BoundTypeArgLt => {
            TokenKind::Lt
        }
        TokenKind::TypeArgGt | TokenKind::GenericParamGt | TokenKind::BoundTypeArgGt => {
            TokenKind::Gt
        }
        TokenKind::TypeAmpersand => TokenKind::Ampersand,
        TokenKind::ReturnArrow | TokenKind::MatchArrow => TokenKind::Arrow,
        TokenKind::ImplPub | TokenKind::TraitPub => TokenKind::Pub,
        TokenKind::ImportString => TokenKind::String,
        TokenKind::ImplFor => TokenKind::For,
        TokenKind::ParamSelfValue | TokenKind::ParamSelfRefValue => TokenKind::SelfValue,
        TokenKind::BoundTypeAmpersand => TokenKind::Ampersand,
        TokenKind::InherentImpl | TokenKind::TraitImpl => TokenKind::Impl,
        other => other,
    }
}

#[test]
fn test_cpu_lexer_oracle_retags_bool_keywords() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("let t = true; let f = false;")
        .expect("test CPU oracle lex")
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
fn test_cpu_lexer_oracle_retags_const_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("const LIMIT: i32 = 7;")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![Const, Ident, Colon, TypeIdent, Assign, Int, Semicolon]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_type_alias_rhs_as_type_context() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("type Count = i32;")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Type,
            TypeAliasNameIdent,
            TypeAliasAssign,
            TypeIdent,
            TypeAliasSemicolon,
        ]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_enum_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("enum Ordering { Less, Equal, Greater }")
        .expect("test CPU oracle lex")
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
fn test_cpu_lexer_oracle_retags_struct_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("struct VecHeader { len: i32 }")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![Struct, Ident, LBrace, Ident, Colon, TypeIdent, RBrace]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_impl_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("impl VecHeader { pub fn len() -> i32 { return 0; } }")
        .expect("test CPU oracle lex")
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
fn test_cpu_lexer_oracle_retags_trait_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("trait Eq<T> { fn eq(left: T, right: T) -> bool; }")
        .expect("test CPU oracle lex")
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
fn test_cpu_lexer_oracle_splits_nested_generic_closers_in_type_contexts() {
    use TokenKind::*;

    let kinds =
        lex_on_test_cpu("fn same<T: Eq<T>>(left: T, right: T) -> bool { return left.eq(right); }")
            .expect("test CPU oracle lex")
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
fn test_cpu_lexer_oracle_splits_nested_generic_closers_after_multiple_bounds() {
    use TokenKind::*;

    let kinds =
        lex_on_test_cpu("fn key<T: Eq<T> + Hash<T>>(value: T) -> u32 { return value.hash(); }")
            .expect("test CPU oracle lex")
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
fn test_cpu_lexer_oracle_retags_for_in_keywords() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("for item in values { continue; }")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![For, Ident, In, Ident, LBrace, Continue, Semicolon, RBrace]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_extern_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu(r#"pub extern "wasm" fn host_alloc(size: usize) -> u32;"#)
        .expect("test CPU oracle lex")
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
fn test_cpu_lexer_oracle_retags_type_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("pub type Count = i32;")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Pub,
            Type,
            TypeAliasNameIdent,
            TypeAliasAssign,
            TypeIdent,
            TypeAliasSemicolon,
        ]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_where_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("fn keep<T>(value: T) -> T where T: Eq<T> { return value; }")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert!(kinds.contains(&Where));
}

#[test]
fn test_cpu_lexer_oracle_retags_self_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("impl Range { fn start(self) -> i32 { return self.start; } }")
        .expect("test CPU oracle lex")
        .into_iter()
        .map(|token| token.kind)
        .collect::<Vec<_>>();

    assert_eq!(
        kinds,
        vec![
            Impl,
            Ident,
            LBrace,
            Fn,
            Ident,
            ParamLParen,
            SelfValue,
            ParamRParen,
            Arrow,
            TypeIdent,
            LBrace,
            Return,
            SelfValue,
            Dot,
            Ident,
            Semicolon,
            RBrace,
            RBrace,
        ]
    );
}

#[test]
fn test_cpu_lexer_oracle_retags_match_keyword() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("match (value) { _ -> value }")
        .expect("test CPU oracle lex")
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
fn test_cpu_lexer_oracle_retags_module_and_import_keywords() {
    use TokenKind::*;

    let kinds = lex_on_test_cpu("module core::i32; import core::bool; import \"stdlib/i32.lani\";")
        .expect("test CPU oracle lex")
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

#[test]
fn gpu_parser_boundary_builds_semantic_context_tokens_on_gpu() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU parser semantic token boundary", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("parse tables");
        let src = "fn main() { return -a + f(b)[c] + [d] + (e); }";

        let semantic = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.debug_semantic_token_kinds_for_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex")
            .expect("semantic token kinds");

        let expected = [
            0u32,
            Fn as u32,
            Ident as u32,
            ParamLParen as u32,
            ParamRParen as u32,
            FnBlockLBrace as u32,
            Return as u32,
            PrefixMinus as u32,
            Ident as u32,
            InfixPlus as u32,
            Ident as u32,
            CallLParen as u32,
            Ident as u32,
            CallRParen as u32,
            IndexLBracket as u32,
            Ident as u32,
            IndexRBracket as u32,
            InfixPlus as u32,
            ArrayLBracket as u32,
            Ident as u32,
            ArrayRBracket as u32,
            InfixPlus as u32,
            GroupLParen as u32,
            Ident as u32,
            GroupRParen as u32,
            ReturnSemicolon as u32,
            FnBlockRBrace as u32,
            0u32,
        ];

        assert_eq!(semantic, expected);
    });
}

#[test]
fn gpu_parser_boundary_emits_language_feature_flags_on_gpu() {
    const FEATURE_TYPE_ARGS: u32 = 0x00000001;
    const FEATURE_ARRAYS: u32 = 0x00000002;
    const FEATURE_ENUMS: u32 = 0x00000004;
    const FEATURE_MATCHES: u32 = 0x00000008;
    const FEATURE_STRUCTS: u32 = 0x00000010;
    const ALL_FEATURES: u32 =
        FEATURE_TYPE_ARGS | FEATURE_ARRAYS | FEATURE_ENUMS | FEATURE_MATCHES | FEATURE_STRUCTS;

    common::block_on_gpu_with_timeout("GPU parser token feature flags", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("parse tables");

        let plain = "fn main() { let x = 1 + 2; return x; }";
        let plain_flags = lexer
            .with_resident_tokens(plain, |_, _, bufs| {
                parser.debug_token_feature_flags_for_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )
            })
            .await
            .expect("plain resident lex")
            .expect("plain token feature flags");
        assert_eq!(plain_flags & ALL_FEATURES, 0);

        let featured = "\
struct Box<T> { value: [i32; 2] }\n\
enum Choice { A, B(i32) }\n\
fn main() { let b = Box { value: [1, 2] }; match (Choice::A) { Choice::A => 1, Choice::B(v) => v, }; return 0; }";
        let featured_flags = lexer
            .with_resident_tokens(featured, |_, _, bufs| {
                parser.debug_token_feature_flags_for_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )
            })
            .await
            .expect("featured resident lex")
            .expect("featured token feature flags");
        assert_eq!(featured_flags & ALL_FEATURES, ALL_FEATURES);
    });
}

#[test]
fn gpu_parser_boundary_retags_nested_if_condition_block_as_block() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU parser nested if block token boundary", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("parse tables");
        let src = "fn main() { let ok: bool = true; if (ok || (1 > 2)) { print(1); } return 0; }";

        let semantic = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.debug_semantic_token_kinds_for_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex")
            .expect("semantic token kinds");

        let if_pos = semantic
            .iter()
            .position(|&kind| kind == If as u32)
            .expect("fixture should contain if token");
        let expected = [
            If as u32,
            GroupLParen as u32,
            Ident as u32,
            OrOr as u32,
            GroupLParen as u32,
            Int as u32,
            Gt as u32,
            Int as u32,
            GroupRParen as u32,
            GroupRParen as u32,
            LBrace as u32,
            Ident as u32,
            CallLParen as u32,
            Int as u32,
            CallRParen as u32,
            ExprSemicolon as u32,
            RBrace as u32,
        ];

        assert_eq!(&semantic[if_pos..if_pos + expected.len()], expected);
    });
}

#[test]
fn gpu_parser_boundary_retags_tuple_match_arm_arrow_as_match_arrow() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU parser tuple match arm arrow boundary", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("parse tables");
        let src = "fn main(value: Option) -> bool { return match (value) { Some(inner) -> check(1, (2 + 3)), None -> false, }; }";

        let semantic = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.debug_semantic_token_kinds_for_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex")
            .expect("semantic token kinds");

        let match_pos = semantic
            .iter()
            .position(|&kind| kind == Match as u32)
            .expect("fixture should contain match token");
        let expected = [
            Match as u32,
            GroupLParen as u32,
            Ident as u32,
            GroupRParen as u32,
            MatchLBrace as u32,
            Ident as u32,
            PatternLParen as u32,
            Ident as u32,
            PatternRParen as u32,
            MatchArrow as u32,
            Ident as u32,
            CallLParen as u32,
            Int as u32,
            ArgComma as u32,
            GroupLParen as u32,
            Int as u32,
            InfixPlus as u32,
            Int as u32,
            GroupRParen as u32,
            CallRParen as u32,
            MatchArmComma as u32,
            Ident as u32,
            MatchArrow as u32,
            False as u32,
            MatchArmComma as u32,
            MatchRBrace as u32,
        ];

        assert_eq!(&semantic[match_pos..match_pos + expected.len()], expected);
    });
}

#[test]
fn gpu_parser_boundary_retags_enum_payload_fields_as_type_names() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU parser enum payload type tokens", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("parse tables");
        let src = "enum Option<T> { Some(T), Pair(T, i32), None }";

        let semantic = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.debug_semantic_token_kinds_for_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex")
            .expect("semantic token kinds");

        let expected = [
            0u32,
            Enum as u32,
            Ident as u32,
            GenericParamLt as u32,
            GenericParamIdent as u32,
            GenericParamGt as u32,
            EnumLBrace as u32,
            Ident as u32,
            EnumPayloadLParen as u32,
            TypeIdent as u32,
            EnumPayloadRParen as u32,
            EnumVariantComma as u32,
            Ident as u32,
            EnumPayloadLParen as u32,
            TypeIdent as u32,
            EnumFieldComma as u32,
            TypeIdent as u32,
            EnumPayloadRParen as u32,
            EnumVariantComma as u32,
            Ident as u32,
            EnumRBrace as u32,
            0u32,
        ];

        assert_eq!(semantic, expected);
    });
}

#[test]
fn gpu_parser_boundary_retags_generic_impl_receiver_type() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU parser generic impl receiver tokens", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("parse tables");
        let src = "impl Range<i32> { fn start(self) -> i32 { return self.start; } }";

        let semantic = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.debug_semantic_token_kinds_for_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex")
            .expect("semantic token kinds");

        let expected = [
            0u32,
            InherentImpl as u32,
            TypeIdent as u32,
            TypeArgLt as u32,
            TypeIdent as u32,
            TypeArgGt as u32,
            ImplLBrace as u32,
            Fn as u32,
            Ident as u32,
            ParamLParen as u32,
            ParamSelfValue as u32,
            ParamRParen as u32,
            ReturnArrow as u32,
            TypeIdent as u32,
            ImplFnBlockLBrace as u32,
            Return as u32,
            SelfValue as u32,
            Dot as u32,
            MemberIdent as u32,
            ReturnSemicolon as u32,
            ImplFnBlockRBrace as u32,
            ImplRBrace as u32,
            0u32,
        ];

        assert_eq!(semantic, expected);
    });
}

#[test]
fn gpu_parser_retags_trait_impl_and_method_braces() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU parser trait impl brace retagging", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("parse tables");
        let src = "trait Eq<T> { fn eq(left: T, right: T) -> bool; } impl Eq<i32> for i32 { fn eq(left: i32, right: i32) -> bool { return left == right; } }";

        let tokens = lexer.lex(src).await.expect("tokens");
        let semantic = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.debug_semantic_token_kinds_for_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex")
            .expect("semantic token kinds");

        let impl_token = tokens
            .iter()
            .position(|token| token.kind == Impl)
            .expect("impl token");
        let impl_open = tokens
            .iter()
            .enumerate()
            .skip(impl_token)
            .find(|(_, token)| token.kind == LBrace)
            .map(|(i, _)| i)
            .expect("impl opening brace");
        let method_open = tokens
            .iter()
            .enumerate()
            .skip(impl_open + 1)
            .find(|(_, token)| token.kind == LBrace)
            .map(|(i, _)| i)
            .expect("method opening brace");
        let method_close = tokens
            .iter()
            .enumerate()
            .skip(method_open + 1)
            .find(|(_, token)| token.kind == RBrace)
            .map(|(i, _)| i)
            .expect("method closing brace");
        let impl_close = tokens
            .iter()
            .enumerate()
            .skip(method_close + 1)
            .find(|(_, token)| token.kind == RBrace)
            .map(|(i, _)| i)
            .expect("impl closing brace");

        assert_eq!(semantic[impl_open + 1], ImplLBrace as u32);
        assert_eq!(semantic[method_open + 1], ImplFnBlockLBrace as u32);
        assert_eq!(semantic[method_close + 1], ImplFnBlockRBrace as u32);
        assert_eq!(semantic[impl_close + 1], ImplRBrace as u32);
    });
}

#[test]
fn gpu_parser_boundary_retags_long_function_close() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU parser long function brace retagging", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("parse tables");
        let mut src = std::string::String::from("fn main() {\n");
        for i in 0..300 {
            src.push_str(&format!("let v{i} = {i};\n"));
        }
        src.push_str("}\n");

        let semantic = lexer
            .with_resident_tokens(&src, |_, _, bufs| {
                parser.debug_semantic_token_kinds_for_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex")
            .expect("semantic token kinds");

        assert_eq!(semantic[5], FnBlockLBrace as u32);
        assert_eq!(semantic[semantic.len() - 2], FnBlockRBrace as u32);
    });
}

#[test]
fn gpu_parser_boundary_retags_adjacent_function_closes() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU parser adjacent function brace retagging", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("parse tables");
        let mut src = std::string::String::new();
        for i in 0..180 {
            let arity = i % 4;
            let params = (0..arity)
                .map(|param_i| format!("p{i}v{param_i}"))
                .collect::<Vec<_>>();
            src.push_str(&format!("fn f{i}("));
            for (param_i, param) in params.iter().enumerate() {
                if param_i != 0 {
                    src.push_str(", ");
                }
                src.push_str(param);
                src.push_str(": i32");
            }
            src.push_str(") -> i32 {\n");
            if arity >= 2 && i % 11 == 5 {
                src.push_str(&format!(
                        "    if ({} < {}) {{\n        return {} + {};\n    }} else {{\n        return {} - {};\n    }}\n",
                        params[0], params[1], params[0], params[1], params[0], params[1]
                    ));
            } else if arity >= 1 && i % 7 == 3 {
                src.push_str(&format!(
                    "    let t{i}: i32 = {} * {};\n    return t{i} + {};\n",
                    params[0],
                    params.get(1).unwrap_or(&params[0]),
                    i % 9
                ));
            } else if arity >= 1 && i % 13 == 6 {
                src.push_str(&format!(
                    "    let a{i}: i32 = {};\n    a{i} += {};\n    return a{i};\n",
                    params[0],
                    i % 7
                ));
            } else if arity == 0 {
                src.push_str(&format!("    return ({} + {});\n", i % 64, (i + 3) % 64));
            } else {
                src.push_str(&format!("    return {} + {};\n", params[0], i % 64));
            }
            src.push_str("}\n");
        }

        let tokens = lexer.lex(&src).await.expect("tokens");
        let semantic = lexer
            .with_resident_tokens(&src, |_, _, bufs| {
                parser.debug_semantic_token_kinds_for_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex")
            .expect("semantic token kinds");

        let mut checked = 0usize;
        for (i, pair) in tokens.windows(2).enumerate() {
            if pair[0].kind == RBrace && pair[1].kind == Fn {
                checked += 1;
                assert_eq!(
                    semantic[i + 1],
                    FnBlockRBrace as u32,
                    "raw token {i} is a function close before another fn"
                );
            }
        }
        assert!(
            checked > 64,
            "generated source should cover many adjacent function boundaries"
        );
    });
}

#[test]
fn gpu_parser_boundary_builds_param_and_type_context_tokens_on_gpu() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU parser parameter/type semantic boundary", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("parse tables");
        let src = "fn add(x: i32, y: [i32; 4]) { let z: [i32; 4] = x; return z; }";

        let semantic = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.debug_semantic_token_kinds_for_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex")
            .expect("semantic token kinds");

        let expected = [
            0u32,
            Fn as u32,
            Ident as u32,
            ParamLParen as u32,
            ParamIdent as u32,
            TypeColon as u32,
            TypeIdent as u32,
            ParamComma as u32,
            ParamIdent as u32,
            TypeColon as u32,
            TypeArrayLBracket as u32,
            TypeIdent as u32,
            TypeSemicolon as u32,
            Int as u32,
            TypeArrayRBracket as u32,
            ParamRParen as u32,
            FnBlockLBrace as u32,
            Let as u32,
            LetIdent as u32,
            TypeColon as u32,
            TypeArrayLBracket as u32,
            TypeIdent as u32,
            TypeSemicolon as u32,
            Int as u32,
            TypeArrayRBracket as u32,
            LetAssign as u32,
            Ident as u32,
            LetSemicolon as u32,
            Return as u32,
            Ident as u32,
            ReturnSemicolon as u32,
            FnBlockRBrace as u32,
            0u32,
        ];

        assert_eq!(semantic, expected);
    });
}

#[test]
fn gpu_parser_boundary_retags_type_alias_rhs_as_type_context() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU parser type alias semantic boundary", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("parse tables");
        let src = "type Count = i32;";

        let semantic = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.debug_semantic_token_kinds_for_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex")
            .expect("semantic token kinds");

        let expected = [
            0u32,
            Type as u32,
            TypeAliasNameIdent as u32,
            TypeAliasAssign as u32,
            TypeIdent as u32,
            TypeAliasSemicolon as u32,
            0u32,
        ];

        assert_eq!(semantic, expected);
    });
}

#[test]
fn gpu_parser_boundary_retags_type_alias_array_rhs_from_statement_context() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout(
        "GPU parser type alias array semantic boundary",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("parse tables");
            let src = "type Four = [i32; 4];";

            let semantic = lexer
                .with_resident_tokens(src, |_, _, bufs| {
                    parser.debug_semantic_token_kinds_for_resident_tokens(
                        bufs.n,
                        &bufs.tokens_out,
                        &bufs.token_count,
                        &tables,
                    )
                })
                .await
                .expect("resident lex")
                .expect("semantic token kinds");

            let expected = [
                0u32,
                Type as u32,
                TypeAliasNameIdent as u32,
                TypeAliasAssign as u32,
                TypeArrayLBracket as u32,
                TypeIdent as u32,
                TypeSemicolon as u32,
                Int as u32,
                TypeArrayRBracket as u32,
                TypeAliasSemicolon as u32,
                0u32,
            ];

            assert_eq!(semantic, expected);
        },
    );
}

#[test]
fn gpu_parser_boundary_retags_generic_function_params_on_gpu() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU parser generic function param boundary", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("parse tables");
        let src = "fn unwrap_or<T, E>(value: Result<T, E>, fallback: T) -> T { return fallback; }";

        let semantic = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.debug_semantic_token_kinds_for_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex")
            .expect("semantic token kinds");

        let expected = [
            0u32,
            Fn as u32,
            Ident as u32,
            GenericParamLt as u32,
            GenericParamIdent as u32,
            GenericParamComma as u32,
            GenericParamIdent as u32,
            GenericParamGt as u32,
            ParamLParen as u32,
            ParamIdent as u32,
            TypeColon as u32,
            TypeIdent as u32,
            TypeArgLt as u32,
            TypeIdent as u32,
            TypeArgComma as u32,
            TypeIdent as u32,
            TypeArgGt as u32,
            ParamComma as u32,
            ParamIdent as u32,
            TypeColon as u32,
            TypeIdent as u32,
            ParamRParen as u32,
            ReturnArrow as u32,
            TypeIdent as u32,
        ];

        assert_eq!(&semantic[..expected.len()], expected);
    });
}

#[test]
fn gpu_parser_boundary_keeps_typed_let_initializer_plus_as_infix() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout(
        "GPU parser typed let initializer plus retagging",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("parse tables");
            let src = "fn main() { let b: i32 = a + 20; }";

            let semantic = lexer
                .with_resident_tokens(src, |_, _, bufs| {
                    parser.debug_semantic_token_kinds_for_resident_tokens(
                        bufs.n,
                        &bufs.tokens_out,
                        &bufs.token_count,
                        &tables,
                    )
                })
                .await
                .expect("resident lex")
                .expect("semantic token kinds");

            let expected = [
                0u32,
                Fn as u32,
                Ident as u32,
                ParamLParen as u32,
                ParamRParen as u32,
                FnBlockLBrace as u32,
                Let as u32,
                LetIdent as u32,
                TypeColon as u32,
                TypeIdent as u32,
                LetAssign as u32,
                Ident as u32,
                InfixPlus as u32,
                Int as u32,
                LetSemicolon as u32,
                FnBlockRBrace as u32,
                0u32,
            ];

            assert_eq!(semantic, expected);
        },
    );
}

#[test]
fn gpu_lexer_lexes_correctly_after_source_shrink() {
    common::block_on_gpu_with_timeout("GPU lexer after stdlib source shrink", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let _ = lexer
            .lex(include_str!("../stdlib/array_i32_4.lani"))
            .await
            .expect("lex larger array_i32_4 seed before shrinking");
        let _ = lexer
            .lex(include_str!("../stdlib/bool.lani"))
            .await
            .expect("lex smaller bool seed before i32");
        let gpu_tokens = lexer
            .lex(include_str!("../stdlib/i32.lani"))
            .await
            .expect("lex i32 after resident buffer reuse");
        let cpu_tokens = lex_on_test_cpu(include_str!("../stdlib/i32.lani"))
            .expect("test CPU lexer oracle for i32 seed");

        assert_eq!(
            gpu_tokens.len(),
            cpu_tokens.len(),
            "resident GPU lexer token count should match the test-only CPU oracle"
        );

        for (i, (gpu, cpu)) in gpu_tokens.iter().zip(cpu_tokens.iter()).enumerate() {
            assert_eq!(
                (normalized_reuse_kind(gpu.kind), gpu.start, gpu.len,),
                (normalized_reuse_kind(cpu.kind), cpu.start, cpu.len,),
                "resident GPU lexer token {i} should match the test-only CPU oracle"
            );
        }
    });
}

#[test]
fn gpu_lexer_retags_where_keyword() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU lexer where keyword retagging", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex("where elsewhere").await.expect("lex");
        let kinds = tokens
            .into_iter()
            .map(|token| token.kind)
            .collect::<Vec<_>>();

        assert_eq!(kinds, vec![Where, Ident]);
    });
}

#[test]
fn gpu_lexer_retags_self_keyword() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout("GPU lexer self keyword retagging", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex("self selfish").await.expect("lex");
        let kinds = tokens
            .into_iter()
            .map(|token| token.kind)
            .collect::<Vec<_>>();

        assert_eq!(kinds, vec![SelfValue, Ident]);
    });
}
