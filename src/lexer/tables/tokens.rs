// src/lexer/tables/tokens.rs

/// Token kinds for the MVP grammar.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum TokenKind {
    Ident = 1,
    Int = 2,
    White = 3,

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
}

impl core::convert::TryFrom<u32> for TokenKind {
    type Error = ();
    fn try_from(v: u32) -> Result<Self, ()> {
        TokenKind::from_u32(v).ok_or(())
    }
}

impl TokenKind {
    pub fn from_u32(v: u32) -> Option<Self> {
        let k = match v {
            x if x == TokenKind::Ident as u32 => TokenKind::Ident,
            x if x == TokenKind::Int as u32 => TokenKind::Int,
            x if x == TokenKind::White as u32 => TokenKind::White,
            x if x == TokenKind::LParen as u32 => TokenKind::LParen,
            x if x == TokenKind::RParen as u32 => TokenKind::RParen,
            x if x == TokenKind::Plus as u32 => TokenKind::Plus,
            x if x == TokenKind::Star as u32 => TokenKind::Star,
            x if x == TokenKind::Assign as u32 => TokenKind::Assign,
            x if x == TokenKind::Slash as u32 => TokenKind::Slash,
            x if x == TokenKind::LineComment as u32 => TokenKind::LineComment,
            x if x == TokenKind::BlockComment as u32 => TokenKind::BlockComment,
            x if x == TokenKind::Lt as u32 => TokenKind::Lt,
            x if x == TokenKind::Gt as u32 => TokenKind::Gt,
            x if x == TokenKind::Le as u32 => TokenKind::Le,
            x if x == TokenKind::Ge as u32 => TokenKind::Ge,
            x if x == TokenKind::EqEq as u32 => TokenKind::EqEq,
            x if x == TokenKind::AndAnd as u32 => TokenKind::AndAnd,
            x if x == TokenKind::OrOr as u32 => TokenKind::OrOr,
            x if x == TokenKind::Not as u32 => TokenKind::Not,
            x if x == TokenKind::LBracket as u32 => TokenKind::LBracket,
            x if x == TokenKind::RBracket as u32 => TokenKind::RBracket,
            x if x == TokenKind::LBrace as u32 => TokenKind::LBrace,
            x if x == TokenKind::RBrace as u32 => TokenKind::RBrace,
            x if x == TokenKind::AngleGeneric as u32 => TokenKind::AngleGeneric,
            x if x == TokenKind::Ampersand as u32 => TokenKind::Ampersand,
            x if x == TokenKind::Pipe as u32 => TokenKind::Pipe,
            x if x == TokenKind::Minus as u32 => TokenKind::Minus,
            x if x == TokenKind::CallLParen as u32 => TokenKind::CallLParen,
            x if x == TokenKind::GroupLParen as u32 => TokenKind::GroupLParen,
            x if x == TokenKind::IndexLBracket as u32 => TokenKind::IndexLBracket,
            x if x == TokenKind::ArrayLBracket as u32 => TokenKind::ArrayLBracket,
            x if x == TokenKind::String as u32 => TokenKind::String,
            x if x == TokenKind::Float as u32 => TokenKind::Float,
            x if x == TokenKind::Char as u32 => TokenKind::Char,
            x if x == TokenKind::Dot as u32 => TokenKind::Dot,
            x if x == TokenKind::Comma as u32 => TokenKind::Comma,
            x if x == TokenKind::Semicolon as u32 => TokenKind::Semicolon,
            x if x == TokenKind::Colon as u32 => TokenKind::Colon,
            x if x == TokenKind::Question as u32 => TokenKind::Question,
            x if x == TokenKind::NotEqual as u32 => TokenKind::NotEqual,
            x if x == TokenKind::Percent as u32 => TokenKind::Percent,
            x if x == TokenKind::Caret as u32 => TokenKind::Caret,
            x if x == TokenKind::Shl as u32 => TokenKind::Shl,
            x if x == TokenKind::Shr as u32 => TokenKind::Shr,
            x if x == TokenKind::Tilde as u32 => TokenKind::Tilde,
            x if x == TokenKind::PlusAssign as u32 => TokenKind::PlusAssign,
            x if x == TokenKind::MinusAssign as u32 => TokenKind::MinusAssign,
            x if x == TokenKind::StarAssign as u32 => TokenKind::StarAssign,
            x if x == TokenKind::SlashAssign as u32 => TokenKind::SlashAssign,
            x if x == TokenKind::PercentAssign as u32 => TokenKind::PercentAssign,
            x if x == TokenKind::CaretAssign as u32 => TokenKind::CaretAssign,
            x if x == TokenKind::ShlAssign as u32 => TokenKind::ShlAssign,
            x if x == TokenKind::ShrAssign as u32 => TokenKind::ShrAssign,
            x if x == TokenKind::AmpAssign as u32 => TokenKind::AmpAssign,
            x if x == TokenKind::PipeAssign as u32 => TokenKind::PipeAssign,
            x if x == TokenKind::Inc as u32 => TokenKind::Inc,
            x if x == TokenKind::Dec as u32 => TokenKind::Dec,
            x if x == TokenKind::PrefixPlus as u32 => TokenKind::PrefixPlus,
            x if x == TokenKind::InfixPlus as u32 => TokenKind::InfixPlus,
            x if x == TokenKind::PrefixMinus as u32 => TokenKind::PrefixMinus,
            x if x == TokenKind::InfixMinus as u32 => TokenKind::InfixMinus,
            x if x == TokenKind::GroupRParen as u32 => TokenKind::GroupRParen,
            x if x == TokenKind::CallRParen as u32 => TokenKind::CallRParen,
            x if x == TokenKind::ArrayRBracket as u32 => TokenKind::ArrayRBracket,
            x if x == TokenKind::IndexRBracket as u32 => TokenKind::IndexRBracket,
            x if x == TokenKind::Pub as u32 => TokenKind::Pub,
            x if x == TokenKind::Fn as u32 => TokenKind::Fn,
            x if x == TokenKind::Let as u32 => TokenKind::Let,
            x if x == TokenKind::Return as u32 => TokenKind::Return,
            x if x == TokenKind::If as u32 => TokenKind::If,
            x if x == TokenKind::Else as u32 => TokenKind::Else,
            x if x == TokenKind::While as u32 => TokenKind::While,
            x if x == TokenKind::Break as u32 => TokenKind::Break,
            x if x == TokenKind::Continue as u32 => TokenKind::Continue,
            x if x == TokenKind::Arrow as u32 => TokenKind::Arrow,
            x if x == TokenKind::ParamLParen as u32 => TokenKind::ParamLParen,
            x if x == TokenKind::ParamRParen as u32 => TokenKind::ParamRParen,
            x if x == TokenKind::LetIdent as u32 => TokenKind::LetIdent,
            x if x == TokenKind::ParamIdent as u32 => TokenKind::ParamIdent,
            x if x == TokenKind::TypeIdent as u32 => TokenKind::TypeIdent,
            x if x == TokenKind::LetAssign as u32 => TokenKind::LetAssign,
            x if x == TokenKind::ArgComma as u32 => TokenKind::ArgComma,
            x if x == TokenKind::ArrayComma as u32 => TokenKind::ArrayComma,
            x if x == TokenKind::ParamComma as u32 => TokenKind::ParamComma,
            x if x == TokenKind::TypeArrayLBracket as u32 => TokenKind::TypeArrayLBracket,
            x if x == TokenKind::TypeArrayRBracket as u32 => TokenKind::TypeArrayRBracket,
            x if x == TokenKind::TypeSemicolon as u32 => TokenKind::TypeSemicolon,
            x if x == TokenKind::IfLBrace as u32 => TokenKind::IfLBrace,
            x if x == TokenKind::IfRBrace as u32 => TokenKind::IfRBrace,
            x if x == TokenKind::True as u32 => TokenKind::True,
            x if x == TokenKind::False as u32 => TokenKind::False,
            x if x == TokenKind::Const as u32 => TokenKind::Const,
            _ => return None,
        };
        Some(k)
    }

    pub fn from_name(name: &str) -> Option<Self> {
        let k = match name {
            "Ident" => TokenKind::Ident,
            "Int" => TokenKind::Int,
            "White" => TokenKind::White,
            "LParen" => TokenKind::LParen,
            "RParen" => TokenKind::RParen,
            "Plus" => TokenKind::Plus,
            "Star" => TokenKind::Star,
            "Assign" => TokenKind::Assign,
            "Slash" => TokenKind::Slash,
            "LineComment" => TokenKind::LineComment,
            "BlockComment" => TokenKind::BlockComment,
            "Lt" => TokenKind::Lt,
            "Gt" => TokenKind::Gt,
            "Le" => TokenKind::Le,
            "Ge" => TokenKind::Ge,
            "EqEq" => TokenKind::EqEq,
            "AndAnd" => TokenKind::AndAnd,
            "OrOr" => TokenKind::OrOr,
            "Not" => TokenKind::Not,
            "LBracket" => TokenKind::LBracket,
            "RBracket" => TokenKind::RBracket,
            "LBrace" => TokenKind::LBrace,
            "RBrace" => TokenKind::RBrace,
            "AngleGeneric" => TokenKind::AngleGeneric,
            "Ampersand" => TokenKind::Ampersand,
            "Pipe" => TokenKind::Pipe,
            "Minus" => TokenKind::Minus,
            "CallLParen" => TokenKind::CallLParen,
            "GroupLParen" => TokenKind::GroupLParen,
            "IndexLBracket" => TokenKind::IndexLBracket,
            "ArrayLBracket" => TokenKind::ArrayLBracket,
            "String" => TokenKind::String,
            "Float" => TokenKind::Float,
            "Char" => TokenKind::Char,
            "Dot" => TokenKind::Dot,
            "Comma" => TokenKind::Comma,
            "Semicolon" => TokenKind::Semicolon,
            "Colon" => TokenKind::Colon,
            "Question" => TokenKind::Question,
            "NotEqual" => TokenKind::NotEqual,
            "Percent" => TokenKind::Percent,
            "Caret" => TokenKind::Caret,
            "Shl" => TokenKind::Shl,
            "Shr" => TokenKind::Shr,
            "Tilde" => TokenKind::Tilde,
            "PlusAssign" => TokenKind::PlusAssign,
            "MinusAssign" => TokenKind::MinusAssign,
            "StarAssign" => TokenKind::StarAssign,
            "SlashAssign" => TokenKind::SlashAssign,
            "PercentAssign" => TokenKind::PercentAssign,
            "CaretAssign" => TokenKind::CaretAssign,
            "ShlAssign" => TokenKind::ShlAssign,
            "ShrAssign" => TokenKind::ShrAssign,
            "AmpAssign" => TokenKind::AmpAssign,
            "PipeAssign" => TokenKind::PipeAssign,
            "Inc" => TokenKind::Inc,
            "Dec" => TokenKind::Dec,
            "PrefixPlus" => TokenKind::PrefixPlus,
            "InfixPlus" => TokenKind::InfixPlus,
            "PrefixMinus" => TokenKind::PrefixMinus,
            "InfixMinus" => TokenKind::InfixMinus,
            "GroupRParen" => TokenKind::GroupRParen,
            "CallRParen" => TokenKind::CallRParen,
            "ArrayRBracket" => TokenKind::ArrayRBracket,
            "IndexRBracket" => TokenKind::IndexRBracket,
            "Pub" => TokenKind::Pub,
            "Fn" => TokenKind::Fn,
            "Let" => TokenKind::Let,
            "Return" => TokenKind::Return,
            "If" => TokenKind::If,
            "Else" => TokenKind::Else,
            "While" => TokenKind::While,
            "Break" => TokenKind::Break,
            "Continue" => TokenKind::Continue,
            "Arrow" => TokenKind::Arrow,
            "ParamLParen" => TokenKind::ParamLParen,
            "ParamRParen" => TokenKind::ParamRParen,
            "LetIdent" => TokenKind::LetIdent,
            "ParamIdent" => TokenKind::ParamIdent,
            "TypeIdent" => TokenKind::TypeIdent,
            "LetAssign" => TokenKind::LetAssign,
            "ArgComma" => TokenKind::ArgComma,
            "ArrayComma" => TokenKind::ArrayComma,
            "ParamComma" => TokenKind::ParamComma,
            "TypeArrayLBracket" => TokenKind::TypeArrayLBracket,
            "TypeArrayRBracket" => TokenKind::TypeArrayRBracket,
            "TypeSemicolon" => TokenKind::TypeSemicolon,
            "IfLBrace" => TokenKind::IfLBrace,
            "IfRBrace" => TokenKind::IfRBrace,
            "True" => TokenKind::True,
            "False" => TokenKind::False,
            "Const" => TokenKind::Const,
            _ => return None,
        };
        Some(k)
    }
}

// used on GPU side too
pub const INVALID_TOKEN: u32 = u32::MAX;
pub const N_KINDS: u32 = TokenKind::Const as u32 + 1;

#[cfg(test)]
mod tests {
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
}
