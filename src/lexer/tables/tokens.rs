// src/lexer/tables/tokens.rs

macro_rules! define_token_kinds {
    ($($name:ident $(= $value:expr)?),+ $(,)?) => {
        /// Token kinds for the MVP grammar.
        #[derive(Debug, Clone, Copy, PartialEq, Eq)]
        #[repr(u32)]
        pub enum TokenKind {
            $($name $(= $value)?,)+
        }

        impl TokenKind {
            pub const ALL: &'static [Self] = &[
                $(Self::$name,)+
            ];

            pub fn from_u32(v: u32) -> Option<Self> {
                let index = usize::try_from(v).ok()?.checked_sub(1)?;
                Self::ALL
                    .get(index)
                    .copied()
                    .filter(|kind| *kind as u32 == v)
            }

            pub fn from_name(name: &str) -> Option<Self> {
                let k = match name {
                    $(stringify!($name) => Self::$name,)+
                    _ => return None,
                };
                Some(k)
            }
        }
    };
}

define_token_kinds! {
    Ident = 1,
    Int,
    White,

    // single-char punctuation
    LParen = 4,
    RParen = 5,
    Plus = 6,
    Star = 7,
    Assign = 8,
    Slash = 9,
    LineComment = 10,
    BlockComment = 11,

    // comparisons / logic / brackets / braces
    Lt,
    Gt,
    Le,
    Ge,
    EqEq,
    AndAnd,
    OrOr,
    Not,
    LBracket,
    RBracket,
    LBrace,
    RBrace,
    AngleGeneric,

    // optional singles so lone '&' or '|' aren't errors
    Ampersand,
    Pipe,

    // new single-char minus
    Minus,

    // --------- NEW: retagged tokens (must match Slang constants) ---------
    CallLParen,
    GroupLParen,
    IndexLBracket,
    ArrayLBracket,
    String,

    // --------- NEW: literals, punctuation, and operators ---------
    Float,
    Char,

    // punctuation
    Dot,
    Comma,
    Semicolon,
    Colon,
    Question,

    // operators
    NotEqual,
    Percent,
    Caret,
    Shl,
    Shr,
    Tilde,
    PlusAssign,
    MinusAssign,
    StarAssign,
    SlashAssign,
    PercentAssign,
    CaretAssign,
    ShlAssign,
    ShrAssign,
    AmpAssign,
    PipeAssign,
    Inc,
    Dec,

    // local-context operator retags
    PrefixPlus,
    InfixPlus,
    PrefixMinus,
    InfixMinus,

    // matched-opener delimiter retags
    GroupRParen,
    CallRParen,
    ArrayRBracket,
    IndexRBracket,

    // keyword retags from identifier lexemes
    Pub,
    Fn,
    Let,
    Return,
    If,
    Else,
    While,
    Break,
    Continue,
    Arrow,

    // context-specific function signature delimiters
    ParamLParen,
    ParamRParen,

    // grammar-boundary context retags
    LetIdent,
    ParamIdent,
    TypeIdent,
    LetAssign,
    ArgComma,
    ArrayComma,
    ParamComma,
    TypeArrayLBracket,
    TypeArrayRBracket,
    TypeSemicolon,
    IfLBrace,
    IfRBrace,
    True,
    False,
    Const,
    Enum,
    Struct,
    Match,
    Import,
    Module,
    Impl,
    Trait,
    For,
    In,
    Extern,
    Type,
    Where,
    SelfValue,
    DeclAssign,
    BoundColon,
    TypeColon,
    MemberIdent,
    TypeAliasAssign,
    ConstAssign,
    ReturnArrow,
    MatchArrow,
    PathColon,
    PrefixInc,
    PostfixInc,
    PrefixDec,
    PostfixDec,
    MatchLBrace,
    MatchRBrace,
    ImplLBrace,
    ImplRBrace,
    TraitLBrace,
    TraitRBrace,
    StructLitLBrace,
    StructLitRBrace,
    StructDeclLBrace,
    StructDeclRBrace,
    EnumLBrace,
    EnumRBrace,
    TypeArgLt,
    TypeArgGt,
    GenericParamLt,
    GenericParamGt,
    TypeArgComma,
    GenericParamComma,
    EnumFieldComma,
    MatchArmComma,
    PatternComma,
    PatternLParen,
    PatternRParen,
    EnumPayloadLParen,
    EnumPayloadRParen,
    TypeAmpersand,
    BoundPlus,
    TraitMethodSemicolon,
    ImplPub,
    TraitPub,
    FnBlockLBrace,
    FnBlockRBrace,
    ImplFnBlockLBrace,
    ImplFnBlockRBrace,
    TypeAliasNameIdent,
    TraitNameIdent,
    GenericParamIdent,
    WhereIdent,
    WhereComma,
    EnumVariantComma,
    StructFieldComma,
    StructLitComma,
    ImportString,
    ImportSemicolon,
    ModuleSemicolon,
    ExternSemicolon,
    TypeAliasSemicolon,
    ConstSemicolon,
    LetSemicolon,
    ReturnSemicolon,
    ExprSemicolon,
    BreakSemicolon,
    ContinueSemicolon,
    ImplFor,
    ParamSelfValue,
    BoundTypeIdent,
    BoundTypeArgLt,
    BoundTypeArgGt,
    BoundTypeArgComma,
    ParamSelfRefValue,
    BoundTypeAmpersand,
    InherentImpl,
    TraitImpl,
    DotDot,
    RangeEndIdent,
    PathTypeArgLt,
    PathTypeArgGt,
    PathTypeArgComma,
    PathGenericIdent,
    ExternAbiString,
    DotDotEqual,
    RangeInclusiveAssign,
}

impl core::convert::TryFrom<u32> for TokenKind {
    type Error = ();
    fn try_from(v: u32) -> Result<Self, ()> {
        TokenKind::from_u32(v).ok_or(())
    }
}

// used on GPU side too
pub const INVALID_TOKEN: u32 = u32::MAX;
pub const N_KINDS: u32 = TokenKind::ALL.len() as u32 + 1;

#[cfg(test)]
mod tests {
    use std::{
        fs,
        path::{Path, PathBuf},
    };

    use super::*;

    #[test]
    fn from_u32_covers_contiguous_token_range() {
        assert_eq!(TokenKind::from_u32(0), None);
        for v in 1..N_KINDS {
            let kind = TokenKind::from_u32(v)
                .unwrap_or_else(|| panic!("missing TokenKind::from_u32 mapping for {v}"));
            assert_eq!(kind as u32, v);
        }
        assert_eq!(TokenKind::from_u32(N_KINDS), None);
        assert_eq!(TokenKind::from_u32(0xFFFF), None);
        assert_eq!(TokenKind::from_u32(INVALID_TOKEN), None);
        assert!(TokenKind::try_from(INVALID_TOKEN).is_err());
    }

    #[test]
    fn grammar_terminal_names_resolve() {
        let grammar = include_str!("../../../grammar/lanius.bnf");
        for line in grammar.lines().map(str::trim) {
            if line.is_empty() || line.starts_with('#') || !line.contains("->") {
                continue;
            }
            for terminal in line.split('\'').skip(1).step_by(2) {
                assert!(
                    TokenKind::from_name(terminal).is_some(),
                    "grammar terminal '{terminal}' is not a TokenKind"
                );
            }
        }
    }

    #[test]
    fn generated_shader_token_ids_match_token_kind_discriminants() {
        let generated = include_str!("../../../shaders/generated_token_ids.slang");
        assert_eq!(
            generated_uint_const(generated, "TOKEN_KIND_COUNT"),
            Some(N_KINDS),
            "generated TOKEN_KIND_COUNT must match N_KINDS"
        );
        assert_eq!(
            generated_uint_const(generated, "TOKEN_INVALID"),
            Some(INVALID_TOKEN),
            "generated TOKEN_INVALID must match INVALID_TOKEN"
        );

        for &kind in TokenKind::ALL {
            let name = format!("TK_{}", screaming_snake_token_name(kind));
            assert_eq!(
                generated_uint_const(generated, &name),
                Some(kind as u32),
                "generated {name} must match TokenKind::{kind:?}"
            );
        }
    }

    #[test]
    fn shader_token_id_constants_match_generated_ids() {
        let generated = include_str!("../../../shaders/generated_token_ids.slang");
        let mut shader_paths = Vec::new();
        collect_slang_paths(
            &Path::new(env!("CARGO_MANIFEST_DIR")).join("shaders"),
            &mut shader_paths,
        );

        for path in shader_paths {
            if path.file_name().and_then(|name| name.to_str()) == Some("generated_token_ids.slang")
            {
                continue;
            }

            let text = fs::read_to_string(&path)
                .unwrap_or_else(|err| panic!("failed to read {}: {err}", path.display()));
            for (line_index, line) in text.lines().enumerate() {
                let Some((name, value)) = shader_token_const(line.trim()) else {
                    continue;
                };
                let generated_name = format!("TK_{name}");
                let Some(expected) = generated_uint_const(generated, &generated_name) else {
                    continue;
                };
                assert_eq!(
                    value,
                    expected,
                    "{}:{} hard-coded {generated_name}={value} must match generated {expected}",
                    path.display(),
                    line_index + 1
                );
            }
        }
    }

    fn generated_uint_const(source: &str, name: &str) -> Option<u32> {
        let prefix = format!("static const uint {name} = ");
        source
            .lines()
            .find_map(|line| line.strip_prefix(&prefix)?.strip_suffix("u;")?.parse().ok())
    }

    fn shader_token_const(line: &str) -> Option<(&str, u32)> {
        let line = line.strip_prefix("static const uint TK_")?;
        let (suffix, value) = line.split_once(" = ")?;
        let value = value
            .strip_suffix("u;")
            .or_else(|| value.strip_suffix(';'))?
            .parse()
            .ok()?;
        Some((&line[..suffix.len()], value))
    }

    fn collect_slang_paths(dir: &Path, out: &mut Vec<PathBuf>) {
        for entry in fs::read_dir(dir)
            .unwrap_or_else(|err| panic!("failed to read {}: {err}", dir.display()))
        {
            let entry = entry.unwrap_or_else(|err| panic!("failed to read dir entry: {err}"));
            let path = entry.path();
            if path.is_dir() {
                collect_slang_paths(&path, out);
            } else if path.extension().and_then(|ext| ext.to_str()) == Some("slang") {
                out.push(path);
            }
        }
    }

    fn screaming_snake_token_name(kind: TokenKind) -> String {
        let name = format!("{kind:?}");
        match name.as_str() {
            "EqEq" => return "EQEQ".to_string(),
            "AndAnd" => return "ANDAND".to_string(),
            "OrOr" => return "OROR".to_string(),
            _ => {}
        }

        let mut out = String::with_capacity(name.len() + 4);
        let mut prev_was_lower_or_digit = false;
        for ch in name.chars() {
            if ch.is_ascii_uppercase() && prev_was_lower_or_digit {
                out.push('_');
            }
            out.push(ch.to_ascii_uppercase());
            prev_was_lower_or_digit = ch.is_ascii_lowercase() || ch.is_ascii_digit();
        }
        out
    }
}
