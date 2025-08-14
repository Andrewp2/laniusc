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
}

impl core::convert::TryFrom<u32> for TokenKind {
    type Error = ();
    fn try_from(v: u32) -> Result<Self, ()> {
        // match all discriminants explicitly
        let k = match v {
            x if x == TokenKind::Ident as u32 => TokenKind::Ident,
            x if x == TokenKind::Int as u32 => TokenKind::Int,
            // ... (generate with a macro if you like)
            _ => return Err(()),
        };
        Ok(k)
    }
}

// used on GPU side too
pub const INVALID_TOKEN: u32 = u32::MAX;
