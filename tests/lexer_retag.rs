mod common;

use laniusc::{
    lexer::{
        GpuToken,
        driver::GpuLexer,
        tables::tokens::TokenKind,
        test_cpu::lex_on_test_cpu,
        util::read_tokens_from_mapped,
    },
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
fn gpu_parser_boundary_retags_long_match_arm_comma_from_brace_records() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout(
        "GPU parser long match arm comma from brace records",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("parse tables");
            let mut src = std::string::String::from(
                "fn main(value: i32) -> i32 { return match value { 0 -> 0",
            );
            for i in 0..700 {
                src.push_str(&format!(" + {i}"));
            }
            src.push_str(", 1 -> 1, }; }");

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

            let arm_commas = semantic
                .iter()
                .filter(|&&kind| kind == MatchArmComma as u32)
                .count();
            assert_eq!(arm_commas, 2);
        },
    );
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
fn gpu_parser_boundary_retags_impl_method_open_from_owner_prefix_records() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout(
        "GPU parser impl method brace owner prefix records",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("parse tables");
            let mut src = std::string::String::from("impl Range<i32> {\n");
            for i in 0..80 {
                src.push_str(&format!("fn filler{i}() -> i32 {{ return {i}; }}\n"));
            }
            let target_start = src.len();
            src.push_str("fn target() -> i32 { return 7; }\n}\n");

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

            let target_fn = tokens
                .iter()
                .position(|token| token.kind == Fn && token.start >= target_start)
                .expect("target method token");
            let target_open = tokens
                .iter()
                .enumerate()
                .skip(target_fn)
                .find(|(_, token)| token.kind == LBrace)
                .map(|(i, _)| i)
                .expect("target method opening brace");

            assert!(
                target_open > 256,
                "target method should be past the first delimiter block"
            );
            assert_eq!(
                semantic[target_open + 1],
                ImplFnBlockLBrace as u32,
                "impl method opening brace should come from brace-owner prefix records"
            );
        },
    );
}

#[test]
fn gpu_parser_boundary_retags_impl_method_close_from_owner_depth_records() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout(
        "GPU parser impl method close owner depth records",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("parse tables");
            let mut src = std::string::String::from("impl Range<i32> {\nfn target() -> i32 {\n");
            for i in 0..320 {
                src.push_str(&format!("let v{i} = {i};\n"));
            }
            src.push_str("return 7;\n}\n}\n");

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

            let method_open = tokens
                .iter()
                .position(|token| token.kind == LBrace && token.start > "impl Range<i32> {".len())
                .expect("method opening brace");
            let method_close = tokens
                .iter()
                .enumerate()
                .skip(method_open + 1)
                .find(|(_, token)| token.kind == RBrace)
                .map(|(i, _)| i)
                .expect("method closing brace");

            assert!(
                method_close - method_open > 1024,
                "fixture should exceed the old bounded matching scan"
            );
            assert_eq!(semantic[method_open + 1], ImplFnBlockLBrace as u32);
            assert_eq!(
                semantic[method_close + 1],
                ImplFnBlockRBrace as u32,
                "impl method closing brace should come from owner/depth records"
            );
        },
    );
}

#[test]
fn gpu_parser_boundary_retags_long_let_semicolon_from_statement_prefix_records() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout(
        "GPU parser long let semicolon statement prefix records",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("parse tables");
            let mut src = std::string::String::from("fn main() { let value: i32 = 0");
            for i in 0..320 {
                src.push_str(&format!(" + {i}"));
            }
            src.push_str("; return value; }");

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

            let let_i = tokens
                .iter()
                .position(|token| token.kind == Let)
                .expect("let token");
            let semicolon_i = tokens
                .iter()
                .enumerate()
                .skip(let_i)
                .find(|(_, token)| token.kind == Semicolon)
                .map(|(i, _)| i)
                .expect("let semicolon");

            assert!(
                semicolon_i - let_i > 512,
                "fixture should exceed the old bounded semicolon scan"
            );
            assert_eq!(
                semantic[semicolon_i + 1],
                LetSemicolon as u32,
                "let semicolon should come from statement-prefix records"
            );
        },
    );
}

#[test]
fn gpu_parser_boundary_retags_long_decl_assign_from_statement_prefix_records() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout(
        "GPU parser long declaration assign statement prefix records",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("parse tables");
            let mut src = std::string::String::from("fn main() { let value: ");
            for i in 0..180 {
                if i != 0 {
                    src.push_str("::");
                }
                src.push_str(&format!("LocalType{i}"));
            }
            src.push_str(" = 0; }\nconst GLOBAL: ");
            for i in 0..180 {
                if i != 0 {
                    src.push_str("::");
                }
                src.push_str(&format!("ConstType{i}"));
            }
            src.push_str(" = 1;");

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

            let let_i = tokens
                .iter()
                .position(|token| token.kind == Let)
                .expect("let token");
            let let_assign_i = tokens
                .iter()
                .enumerate()
                .skip(let_i)
                .find(|(_, token)| token.kind == Assign)
                .map(|(i, _)| i)
                .expect("let assign token");
            let const_i = tokens
                .iter()
                .position(|token| token.kind == Const)
                .expect("const token");
            let const_assign_i = tokens
                .iter()
                .enumerate()
                .skip(const_i)
                .find(|(_, token)| token.kind == Assign)
                .map(|(i, _)| i)
                .expect("const assign token");

            assert!(
                let_assign_i - let_i > 128,
                "let fixture should exceed the old bounded assignment scan"
            );
            assert!(
                const_assign_i - const_i > 256,
                "const fixture should exceed the old bounded declaration assignment scan"
            );
            assert_eq!(
                semantic[let_assign_i + 1],
                LetAssign as u32,
                "let assignment should come from statement-prefix records"
            );
            assert_eq!(
                semantic[const_assign_i + 1],
                ConstAssign as u32,
                "const assignment should come from statement-prefix records"
            );
        },
    );
}

#[test]
fn gpu_parser_boundary_retags_import_string_from_cross_block_statement_context_records() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout(
        "GPU parser import string statement context records",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("parse tables");
            let mut src = std::string::String::new();
            for i in 0..85 {
                src.push_str(&format!("module filler{i};\n"));
            }
            src.push_str("import \"stdlib/core.lani\";\n");

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

            let import_i = tokens
                .iter()
                .position(|token| token.kind == Import)
                .expect("import token");
            let string_i = import_i + 1;

            assert_eq!(import_i % 256, 255, "import should end a delimiter block");
            assert_eq!(tokens[string_i].kind, String);
            assert_eq!(
                semantic[string_i + 1],
                ImportString as u32,
                "import string should come from cross-block statement context records"
            );
            assert_eq!(semantic[string_i + 2], ImportSemicolon as u32);
        },
    );
}

#[test]
fn gpu_parser_boundary_retags_long_function_close_from_delimiter_records() {
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
fn gpu_parser_boundary_retags_long_struct_literal_close_from_brace_pair_records() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout(
        "GPU parser long struct literal brace pair records",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("parse tables");
            let mut src = std::string::String::from(
                "struct Pair { left: i32, right: i32 }\nfn main() { let p = Pair { left: 0",
            );
            for i in 0..360 {
                src.push_str(&format!(" + {i}"));
            }
            src.push_str(", right: 1 }; return p.left; }");

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

            let literal_open = tokens
                .iter()
                .enumerate()
                .filter(|(_, token)| token.kind == LBrace)
                .nth(2)
                .map(|(i, _)| i)
                .expect("struct literal opening brace");
            let literal_close = tokens
                .iter()
                .enumerate()
                .skip(literal_open + 1)
                .find(|(_, token)| token.kind == RBrace)
                .map(|(i, _)| i)
                .expect("struct literal closing brace");

            assert!(
                literal_close - literal_open > 512,
                "fixture should exceed the old bounded brace-close matching scan"
            );
            assert_eq!(semantic[literal_open + 1], StructLitLBrace as u32);
            assert_eq!(
                semantic[literal_close + 1],
                StructLitRBrace as u32,
                "struct literal closing brace should come from brace pair records"
            );
        },
    );
}

#[test]
fn gpu_parser_boundary_retags_long_array_literal_close_from_bracket_pair_records() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout(
        "GPU parser long array literal bracket pair records",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("parse tables");
            let mut src = std::string::String::from("fn main() { let xs = [0");
            for i in 0..360 {
                src.push_str(&format!(" + {i}"));
            }
            src.push_str(", 1]; return 0; }");

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

            let array_open = tokens
                .iter()
                .enumerate()
                .find(|(_, token)| token.kind == LBracket)
                .map(|(i, _)| i)
                .expect("array literal opening bracket");
            let array_close = tokens
                .iter()
                .enumerate()
                .skip(array_open + 1)
                .find(|(_, token)| token.kind == RBracket)
                .map(|(i, _)| i)
                .expect("array literal closing bracket");
            let array_comma = tokens
                .iter()
                .enumerate()
                .skip(array_open + 1)
                .find(|(_, token)| token.kind == Comma)
                .map(|(i, _)| i)
                .expect("array literal comma");

            assert!(
                array_close - array_open > 512,
                "fixture should exceed the old bounded bracket-close matching scan"
            );
            assert!(
                array_comma - array_open > 512,
                "fixture should exceed the old bounded bracket-comma matching scan"
            );
            assert_eq!(semantic[array_open + 1], ArrayLBracket as u32);
            assert_eq!(
                semantic[array_comma + 1],
                ArrayComma as u32,
                "array literal comma should come from bracket pair records"
            );
            assert_eq!(
                semantic[array_close + 1],
                ArrayRBracket as u32,
                "array literal closing bracket should come from bracket pair records"
            );
        },
    );
}

#[test]
fn gpu_parser_boundary_retags_long_type_array_semicolon_from_bracket_pair_records() {
    use TokenKind::*;

    common::block_on_gpu_with_timeout(
        "GPU parser long type-array semicolon bracket pair records",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("parse tables");

            for case_i in 0..3 {
                let fn_name = format!("shape_fn_{case_i}");
                let param_name = format!("buffer_{case_i}");
                let mut src = format!("fn {fn_name}({param_name}: [TypeHead{case_i}");
                for term_i in 0..360 {
                    src.push_str(&format!(" + Segment{case_i}_{term_i}"));
                }
                src.push_str("; 4]) { return; }");

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

                let array_open = tokens
                    .iter()
                    .enumerate()
                    .find(|(_, token)| token.kind == LBracket)
                    .map(|(i, _)| i)
                    .expect("type-array opening bracket");
                let semicolon_i = tokens
                    .iter()
                    .enumerate()
                    .skip(array_open + 1)
                    .find(|(_, token)| token.kind == Semicolon)
                    .map(|(i, _)| i)
                    .expect("type-array semicolon");

                assert!(
                    semicolon_i - array_open > 512,
                    "fixture should exceed the old bounded type-array semicolon scan"
                );
                assert_eq!(semantic[array_open + 1], TypeArrayLBracket as u32);
                assert_eq!(
                    semantic[semicolon_i + 1],
                    TypeSemicolon as u32,
                    "type-array semicolon should come from bracket pair records"
                );
            }
        },
    );
}

#[test]
fn gpu_parser_boundary_retags_adjacent_function_closes_across_blocks() {
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
fn gpu_lexer_records_single_source_token_file_ids_on_gpu() {
    common::block_on_gpu_with_timeout("GPU lexer single source token file ids", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let src = "module app::main; fn main() { return 0; }";
        let file_ids = lexer
            .with_resident_tokens(src, |device, queue, bufs| {
                let ids_readback = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("rb.test.lexer.token_file_id"),
                    size: bufs.token_file_id.byte_size as u64,
                    usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                    mapped_at_creation: false,
                });
                let count_readback = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("rb.test.lexer.token_count"),
                    size: 4,
                    usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                    mapped_at_creation: false,
                });

                let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("test.lexer.token_file_id.readback"),
                });
                encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &count_readback, 0, 4);
                encoder.copy_buffer_to_buffer(
                    &bufs.token_file_id,
                    0,
                    &ids_readback,
                    0,
                    bufs.token_file_id.byte_size as u64,
                );
                queue.submit(Some(encoder.finish()));

                let count_slice = count_readback.slice(..);
                count_slice.map_async(wgpu::MapMode::Read, |_| {});
                let _ = device.poll(wgpu::PollType::wait_indefinitely());
                let count_bytes = count_slice.get_mapped_range();
                let count = u32::from_le_bytes(count_bytes[0..4].try_into().unwrap()) as usize;
                drop(count_bytes);
                count_readback.unmap();

                let ids_slice = ids_readback.slice(0..(count * 4) as u64);
                ids_slice.map_async(wgpu::MapMode::Read, |_| {});
                let _ = device.poll(wgpu::PollType::wait_indefinitely());
                let ids_bytes = ids_slice.get_mapped_range();
                let ids = ids_bytes
                    .chunks_exact(4)
                    .map(|chunk| u32::from_le_bytes(chunk.try_into().unwrap()))
                    .collect::<Vec<_>>();
                drop(ids_bytes);
                ids_readback.unmap();
                ids
            })
            .await
            .expect("resident lex");

        assert!(!file_ids.is_empty(), "fixture should produce tokens");
        assert!(
            file_ids.iter().all(|file_id| *file_id == 0),
            "single-source tokens should all be assigned to file 0: {file_ids:?}"
        );
    });
}

#[test]
fn gpu_lexer_records_source_pack_token_file_ids_on_gpu() {
    common::block_on_gpu_with_timeout("GPU lexer source pack token file ids", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let sources = [
            "module first; // comment without newline",
            "module second; import first; fn second() { return; }",
        ];
        let boundary = sources[0].len();
        let (tokens, file_ids) = lexer
            .with_resident_source_pack_tokens(&sources, |device, queue, bufs| {
                let tokens_readback = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("rb.test.lexer.source_pack.tokens"),
                    size: bufs.tokens_out.byte_size as u64,
                    usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                    mapped_at_creation: false,
                });
                let ids_readback = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("rb.test.lexer.source_pack.token_file_id"),
                    size: bufs.token_file_id.byte_size as u64,
                    usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                    mapped_at_creation: false,
                });
                let count_readback = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("rb.test.lexer.source_pack.token_count"),
                    size: 4,
                    usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                    mapped_at_creation: false,
                });

                let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("test.lexer.source_pack.readback"),
                });
                encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &count_readback, 0, 4);
                encoder.copy_buffer_to_buffer(
                    &bufs.tokens_out,
                    0,
                    &tokens_readback,
                    0,
                    bufs.tokens_out.byte_size as u64,
                );
                encoder.copy_buffer_to_buffer(
                    &bufs.token_file_id,
                    0,
                    &ids_readback,
                    0,
                    bufs.token_file_id.byte_size as u64,
                );
                queue.submit(Some(encoder.finish()));

                let count_slice = count_readback.slice(..);
                count_slice.map_async(wgpu::MapMode::Read, |_| {});
                let _ = device.poll(wgpu::PollType::wait_indefinitely());
                let count_bytes = count_slice.get_mapped_range();
                let count = u32::from_le_bytes(count_bytes[0..4].try_into().unwrap()) as usize;
                drop(count_bytes);
                count_readback.unmap();

                let token_bytes_len = (count * std::mem::size_of::<GpuToken>()) as u64;
                let tokens_slice = tokens_readback.slice(0..token_bytes_len);
                tokens_slice.map_async(wgpu::MapMode::Read, |_| {});
                let _ = device.poll(wgpu::PollType::wait_indefinitely());
                let token_bytes = tokens_slice.get_mapped_range();
                let tokens =
                    read_tokens_from_mapped(&token_bytes, count).expect("source pack tokens");
                drop(token_bytes);
                tokens_readback.unmap();

                let ids_slice = ids_readback.slice(0..(count * 4) as u64);
                ids_slice.map_async(wgpu::MapMode::Read, |_| {});
                let _ = device.poll(wgpu::PollType::wait_indefinitely());
                let ids_bytes = ids_slice.get_mapped_range();
                let ids = ids_bytes
                    .chunks_exact(4)
                    .map(|chunk| u32::from_le_bytes(chunk.try_into().unwrap()))
                    .collect::<Vec<_>>();
                drop(ids_bytes);
                ids_readback.unmap();
                (tokens, ids)
            })
            .await
            .expect("resident source pack lex");

        assert!(!tokens.is_empty(), "fixture should produce tokens");
        assert_eq!(tokens.len(), file_ids.len());
        assert!(
            file_ids.iter().any(|file_id| *file_id == 0)
                && file_ids.iter().any(|file_id| *file_id == 1),
            "source pack should produce token ids for both files: {file_ids:?}"
        );
        for (token, file_id) in tokens.iter().zip(file_ids.iter()) {
            let expected = if token.start < boundary { 0 } else { 1 };
            assert_eq!(
                *file_id, expected,
                "token at byte {} should belong to file {expected}",
                token.start
            );
            if *file_id == 0 {
                assert!(
                    token.start + token.len <= boundary,
                    "file 0 token should not span into file 1: start={} len={}",
                    token.start,
                    token.len
                );
            }
        }
    });
}

#[test]
fn gpu_lexer_reuses_resident_buffers_after_stdlib_source_shrink() {
    common::block_on_gpu_with_timeout(
        "GPU lexer resident reuse after stdlib source shrink",
        async move {
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
        },
    );
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
