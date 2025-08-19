// src/lexer/tables/dfa.rs
use super::tokens::{INVALID_TOKEN, TokenKind};

// DFA states (small hand-built DFA).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum S {
    Start,
    Ident,
    Int,
    Zero,                // saw single leading 0 (could be prefixes)
    White,

    // comments/slash handling
    MaybeSlash,
    LineComment,
    BlockComment,
    BlockStar,
    BlockDone,

    // simple single-char acceptors
    AfterLParen,
    AfterRParen,
    AfterPlus,
    AfterStar,
    AfterAssign,
    AfterMinus, // <--- NEW
    AfterPercent,
    AfterCaret,
    AfterTilde,
    AfterComma,
    AfterSemicolon,
    AfterColon,
    AfterQuestion,
    // '.' can be standalone or start of a float like `.5`
    MaybeDot,

    // singles
    AfterBang,
    AfterLBracket,
    AfterRBracket,
    AfterLBrace,
    AfterRBrace,

    // two-char combos via "maybe" then "done"
    MaybeLess,
    LessEqualDone,
    AngleDone,
    ShlDone,

    MaybeGreater,
    GreaterEqualDone,
    ShrDone,

    MaybeAnd,
    AndAndDone,

    MaybeOr,
    OrOrDone,

    EqEqDone,
    NotEqualDone,

    // numeric separators and floats
    IntAfterUnderscore,
    HexStart,
    Hex,
    HexAfterUnderscore,
    BinStart,
    Bin,
    BinAfterUnderscore,
    OctStart,
    Oct,
    OctAfterUnderscore,

    FloatDot,              // after seeing digits then '.' (accepting)
    FloatFrac,             // fractional digits loop (accepting)
    FloatFracAfterUnderscore,
    MaybeExpFromInt,       // after 'e' or 'E' following an Int (accepts Int on backoff)
    MaybeExpFromFloat,     // after 'e' or 'E' following a Float (accepts Float on backoff)
    FloatExpSign,          // after exponent sign
    FloatExp,              // exponent digits loop (accepting)
    FloatExpAfterUnderscore,

    // strings and chars
    InString,
    StringEscape,
    StringDone,
    InChar,
    CharEscape,
    CharDone,

    // compound ops
    PlusAssignDone,
    MinusAssignDone,
    StarAssignDone,
    SlashAssignDone,
    PercentAssignDone,
    CaretAssignDone,
    AmpAssignDone,
    PipeAssignDone,
    ShlAssignDone,
    ShrAssignDone,

    // ++/--
    IncDone,
    DecDone,

    Reject,
}
impl S {
    #[inline]
    pub fn idx(self) -> usize {
        self as usize
    }
}

pub const N_STATES: usize = 79;
pub const START: S = S::Start;
pub const REJECT: S = S::Reject;

const ALL_STATES: &[S] = &[
    S::Start,
    S::Ident,
    S::Int,
    S::Zero,
    S::White,
    S::MaybeSlash,
    S::LineComment,
    S::BlockComment,
    S::BlockStar,
    S::BlockDone,
    S::AfterLParen,
    S::AfterRParen,
    S::AfterPlus,
    S::AfterStar,
    S::AfterAssign,
    S::AfterMinus, // <--- NEW
    S::AfterPercent,
    S::AfterCaret,
    S::AfterTilde,
    S::AfterComma,
    S::AfterSemicolon,
    S::AfterColon,
    S::AfterQuestion,
    S::MaybeDot,
    S::AfterBang,
    S::AfterLBracket,
    S::AfterRBracket,
    S::AfterLBrace,
    S::AfterRBrace,
    S::MaybeLess,
    S::LessEqualDone,
    S::AngleDone,
    S::ShlDone,
    S::MaybeGreater,
    S::GreaterEqualDone,
    S::ShrDone,
    S::MaybeAnd,
    S::AndAndDone,
    S::MaybeOr,
    S::OrOrDone,
    S::EqEqDone,
    S::NotEqualDone,
    S::IntAfterUnderscore,
    S::HexStart,
    S::Hex,
    S::HexAfterUnderscore,
    S::BinStart,
    S::Bin,
    S::BinAfterUnderscore,
    S::OctStart,
    S::Oct,
    S::OctAfterUnderscore,
    S::FloatDot,
    S::FloatFrac,
    S::FloatFracAfterUnderscore,
    S::MaybeExpFromInt,
    S::MaybeExpFromFloat,
    S::FloatExpSign,
    S::FloatExp,
    S::FloatExpAfterUnderscore,
    S::InString,
    S::StringEscape,
    S::StringDone,
    S::InChar,
    S::CharEscape,
    S::CharDone,
    S::PlusAssignDone,
    S::MinusAssignDone,
    S::StarAssignDone,
    S::SlashAssignDone,
    S::PercentAssignDone,
    S::CaretAssignDone,
    S::AmpAssignDone,
    S::PipeAssignDone,
    S::ShlAssignDone,
    S::ShrAssignDone,
    S::IncDone,
    S::DecDone,
    S::Reject,
];

#[inline]
fn is_alpha(b: u8) -> bool {
    matches!(b, b'a'..=b'z' | b'A'..=b'Z' | b'_')
}
#[inline]
fn is_digit(b: u8) -> bool {
    b.is_ascii_digit()
}
#[inline]
fn is_alnum(b: u8) -> bool {
    is_alpha(b) || is_digit(b)
}
#[inline]
fn is_white(b: u8) -> bool {
    matches!(b, b' ' | b'\t' | b'\r' | b'\n')
}

/// A transition with an 'emit' flag (meaning: the edge emits a token when taken).
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct Next {
    pub state: u16,
    pub emit: bool,
}

/// Fully materialized streaming DFA.
pub struct StreamingDfa {
    pub next: [[Next; 256]; N_STATES], // [state][byte] -> (next, emit)
    pub token_map: [u32; N_STATES],    // token kind per state (or INVALID_TOKEN)
    pub start: u16,
    pub reject: u16,
}

pub(crate) fn token_of_state(s: S) -> Option<TokenKind> {
    use S::*;
    match s {
        Ident => Some(TokenKind::Ident),
        Int => Some(TokenKind::Int),
        Zero => Some(TokenKind::Int),
        White => Some(TokenKind::White),
        MaybeSlash => Some(TokenKind::Slash),
        BlockDone => Some(TokenKind::BlockComment),
        AfterLParen => Some(TokenKind::LParen),
        AfterRParen => Some(TokenKind::RParen),
        AfterPlus => Some(TokenKind::Plus),
        AfterStar => Some(TokenKind::Star),
        AfterAssign => Some(TokenKind::Assign),
        AfterMinus => Some(TokenKind::Minus), // <--- NEW
        AfterPercent => Some(TokenKind::Percent),
        AfterCaret => Some(TokenKind::Caret),
        AfterTilde => Some(TokenKind::Tilde),
        AfterComma => Some(TokenKind::Comma),
        AfterSemicolon => Some(TokenKind::Semicolon),
        AfterColon => Some(TokenKind::Colon),
        AfterQuestion => Some(TokenKind::Question),
        MaybeDot => Some(TokenKind::Dot),
        LineComment => Some(TokenKind::LineComment),

        AfterBang => Some(TokenKind::Not),
        AfterLBracket => Some(TokenKind::LBracket),
        AfterRBracket => Some(TokenKind::RBracket),
        AfterLBrace => Some(TokenKind::LBrace),
        AfterRBrace => Some(TokenKind::RBrace),

        MaybeLess => Some(TokenKind::Lt),
        LessEqualDone => Some(TokenKind::Le),
        AngleDone => Some(TokenKind::AngleGeneric),
        ShlDone => Some(TokenKind::Shl),
        MaybeGreater => Some(TokenKind::Gt),
        GreaterEqualDone => Some(TokenKind::Ge),
        ShrDone => Some(TokenKind::Shr),

        EqEqDone => Some(TokenKind::EqEq),
        MaybeAnd => Some(TokenKind::Ampersand),
        AndAndDone => Some(TokenKind::AndAnd),
        MaybeOr => Some(TokenKind::Pipe),
        OrOrDone => Some(TokenKind::OrOr),
        NotEqualDone => Some(TokenKind::NotEqual),

        HexStart => Some(TokenKind::Int),
        Hex => Some(TokenKind::Int),
        Bin => Some(TokenKind::Int),
        BinStart => Some(TokenKind::Int),
        Oct => Some(TokenKind::Int),
        OctStart => Some(TokenKind::Int),
        IntAfterUnderscore => Some(TokenKind::Int),
        HexAfterUnderscore => Some(TokenKind::Int),
        BinAfterUnderscore => Some(TokenKind::Int),
        OctAfterUnderscore => Some(TokenKind::Int),
        FloatDot => Some(TokenKind::Float),
        FloatFrac => Some(TokenKind::Float),
        FloatExp => Some(TokenKind::Float),
        FloatExpSign => Some(TokenKind::Float),
        FloatFracAfterUnderscore => Some(TokenKind::Float),
        FloatExpAfterUnderscore => Some(TokenKind::Float),
        MaybeExpFromInt => Some(TokenKind::Int),
        MaybeExpFromFloat => Some(TokenKind::Float),

        StringDone => Some(TokenKind::String),
        CharDone => Some(TokenKind::Char),

        PlusAssignDone => Some(TokenKind::PlusAssign),
        MinusAssignDone => Some(TokenKind::MinusAssign),
        StarAssignDone => Some(TokenKind::StarAssign),
        SlashAssignDone => Some(TokenKind::SlashAssign),
        PercentAssignDone => Some(TokenKind::PercentAssign),
        CaretAssignDone => Some(TokenKind::CaretAssign),
        AmpAssignDone => Some(TokenKind::AmpAssign),
        PipeAssignDone => Some(TokenKind::PipeAssign),
        ShlAssignDone => Some(TokenKind::ShlAssign),
        ShrAssignDone => Some(TokenKind::ShrAssign),

        IncDone => Some(TokenKind::Inc),
        DecDone => Some(TokenKind::Dec),
        _ => None,
    }
}

impl Default for StreamingDfa {
    fn default() -> Self {
        Self::new()
    }
}

impl StreamingDfa {
    pub fn new() -> Self {
        let mut next = [[Next {
            state: S::Reject.idx() as u16,
            emit: false,
        }; 256]; N_STATES];

        fn set(next: &mut [[Next; 256]; N_STATES], from: S, bytes: &[u8], to: S) {
            for &b in bytes {
                next[from.idx()][b as usize] = Next {
                    state: to.idx() as u16,
                    emit: false,
                };
            }
        }
        fn set_all_except(next: &mut [[Next; 256]; N_STATES], from: S, except: &[u8], to: S) {
            let mut skip = [false; 256];
            for &e in except {
                skip[e as usize] = true;
            }
            for b in 0u16..=255 {
                if !skip[b as usize] {
                    next[from.idx()][b as usize] = Next {
                        state: to.idx() as u16,
                        emit: false,
                    };
                }
            }
        }

        // Start
        for b in 0u8..=255 {
            let to = if is_alpha(b) {
                S::Ident
            } else if is_digit(b) {
                if b == b'0' { S::Zero } else { S::Int }
            } else if is_white(b) {
                S::White
            } else {
                match b {
                    b'(' => S::AfterLParen,
                    b')' => S::AfterRParen,
                    b'+' => S::AfterPlus,
                    b'*' => S::AfterStar,
                    b'=' => S::AfterAssign,
                    b'-' => S::AfterMinus,
                    b'/' => S::MaybeSlash,
                    b'!' => S::AfterBang,
                    b'[' => S::AfterLBracket,
                    b']' => S::AfterRBracket,
                    b'{' => S::AfterLBrace,
                    b'}' => S::AfterRBrace,
                    b'<' => S::MaybeLess,
                    b'>' => S::MaybeGreater,
                    b'&' => S::MaybeAnd,
                    b'|' => S::MaybeOr,
                    b'%' => S::AfterPercent,
                    b'^' => S::AfterCaret,
                    b'~' => S::AfterTilde,
                    b',' => S::AfterComma,
                    b';' => S::AfterSemicolon,
                    b':' => S::AfterColon,
                    b'?' => S::AfterQuestion,
                    b'.' => S::MaybeDot,
                    b'"' => S::InString,
                    b'\'' => S::InChar,
                    _ => S::Reject,
                }
            };
            next[S::Start.idx()][b as usize] = Next { state: to.idx() as u16, emit: false };
        }

        // Ident
        for b in 0u8..=255 {
            if is_alnum(b) {
                next[S::Ident.idx()][b as usize] = Next {
                    state: S::Ident.idx() as u16,
                    emit: false,
                };
            }
        }

        // Int (no leading 0 handled via Zero)
        for b in b'0'..=b'9' {
            next[S::Int.idx()][b as usize] = Next { state: S::Int.idx() as u16, emit: false };
        }
        // separators and fractional/exponent
        next[S::Int.idx()][b'_' as usize] = Next { state: S::IntAfterUnderscore.idx() as u16, emit: false };
        for b in b'0'..=b'9' {
            next[S::IntAfterUnderscore.idx()][b as usize] = Next { state: S::Int.idx() as u16, emit: false };
        }
        next[S::Int.idx()][b'.' as usize] = Next { state: S::FloatDot.idx() as u16, emit: false };
        next[S::Int.idx()][b'e' as usize] = Next { state: S::MaybeExpFromInt.idx() as u16, emit: false };
        next[S::Int.idx()][b'E' as usize] = Next { state: S::MaybeExpFromInt.idx() as u16, emit: false };

        // Zero (could be prefixes)
        next[S::Zero.idx()][b'x' as usize] = Next { state: S::HexStart.idx() as u16, emit: false };
        next[S::Zero.idx()][b'X' as usize] = Next { state: S::HexStart.idx() as u16, emit: false };
        next[S::Zero.idx()][b'b' as usize] = Next { state: S::BinStart.idx() as u16, emit: false };
        next[S::Zero.idx()][b'B' as usize] = Next { state: S::BinStart.idx() as u16, emit: false };
        next[S::Zero.idx()][b'o' as usize] = Next { state: S::OctStart.idx() as u16, emit: false };
        next[S::Zero.idx()][b'O' as usize] = Next { state: S::OctStart.idx() as u16, emit: false };
        for b in b'0'..=b'9' {
            next[S::Zero.idx()][b as usize] = Next { state: S::Int.idx() as u16, emit: false };
        }
        next[S::Zero.idx()][b'_' as usize] = Next { state: S::IntAfterUnderscore.idx() as u16, emit: false };
        next[S::Zero.idx()][b'.' as usize] = Next { state: S::FloatDot.idx() as u16, emit: false };
        next[S::Zero.idx()][b'e' as usize] = Next { state: S::MaybeExpFromInt.idx() as u16, emit: false };
        next[S::Zero.idx()][b'E' as usize] = Next { state: S::MaybeExpFromInt.idx() as u16, emit: false };

        // Hex
        for b in b'0'..=b'9' {
            next[S::HexStart.idx()][b as usize] = Next { state: S::Hex.idx() as u16, emit: false };
            next[S::Hex.idx()][b as usize] = Next { state: S::Hex.idx() as u16, emit: false };
        }
        for b in b'a'..=b'f' {
            next[S::HexStart.idx()][b as usize] = Next { state: S::Hex.idx() as u16, emit: false };
            next[S::Hex.idx()][b as usize] = Next { state: S::Hex.idx() as u16, emit: false };
        }
        for b in b'A'..=b'F' {
            next[S::HexStart.idx()][b as usize] = Next { state: S::Hex.idx() as u16, emit: false };
            next[S::Hex.idx()][b as usize] = Next { state: S::Hex.idx() as u16, emit: false };
        }
        next[S::Hex.idx()][b'_' as usize] = Next { state: S::HexAfterUnderscore.idx() as u16, emit: false };
        // after underscore requires hex digit
        for b in b'0'..=b'9' {
            next[S::HexAfterUnderscore.idx()][b as usize] = Next { state: S::Hex.idx() as u16, emit: false };
        }
        for b in b'a'..=b'f' {
            next[S::HexAfterUnderscore.idx()][b as usize] = Next { state: S::Hex.idx() as u16, emit: false };
        }
        for b in b'A'..=b'F' {
            next[S::HexAfterUnderscore.idx()][b as usize] = Next { state: S::Hex.idx() as u16, emit: false };
        }

        // Bin
        next[S::BinStart.idx()][b'0' as usize] = Next { state: S::Bin.idx() as u16, emit: false };
        next[S::BinStart.idx()][b'1' as usize] = Next { state: S::Bin.idx() as u16, emit: false };
        next[S::Bin.idx()][b'0' as usize] = Next { state: S::Bin.idx() as u16, emit: false };
        next[S::Bin.idx()][b'1' as usize] = Next { state: S::Bin.idx() as u16, emit: false };
        next[S::Bin.idx()][b'_' as usize] = Next { state: S::BinAfterUnderscore.idx() as u16, emit: false };
        next[S::BinAfterUnderscore.idx()][b'0' as usize] = Next { state: S::Bin.idx() as u16, emit: false };
        next[S::BinAfterUnderscore.idx()][b'1' as usize] = Next { state: S::Bin.idx() as u16, emit: false };

        // Oct
        for b in b'0'..=b'7' {
            next[S::OctStart.idx()][b as usize] = Next { state: S::Oct.idx() as u16, emit: false };
            next[S::Oct.idx()][b as usize] = Next { state: S::Oct.idx() as u16, emit: false };
        }
        next[S::Oct.idx()][b'_' as usize] = Next { state: S::OctAfterUnderscore.idx() as u16, emit: false };
        for b in b'0'..=b'7' {
            next[S::OctAfterUnderscore.idx()][b as usize] = Next { state: S::Oct.idx() as u16, emit: false };
        }

        // Whitespace
        for &b in b" \t\r\n" {
            next[S::White.idx()][b as usize] = Next {
                state: S::White.idx() as u16,
                emit: false,
            };
        }

        // Slash / comments
        set(&mut next, S::MaybeSlash, b"/", S::LineComment);
        set(&mut next, S::MaybeSlash, b"*", S::BlockComment);
        set(&mut next, S::MaybeSlash, b"=", S::SlashAssignDone);

        // LineComment: consume until '\n'
        set_all_except(&mut next, S::LineComment, b"\n", S::LineComment);

        // BlockComment
        set_all_except(&mut next, S::BlockComment, &[], S::BlockComment);
        set(&mut next, S::BlockComment, b"*", S::BlockStar);

        // BlockStar
        set(&mut next, S::BlockStar, b"*", S::BlockStar);
        set(&mut next, S::BlockStar, b"/", S::BlockDone);
        set_all_except(&mut next, S::BlockStar, b"*/", S::BlockComment);

        // Two-char operators
        set(&mut next, S::MaybeLess, b"=", S::LessEqualDone);
        set(&mut next, S::MaybeLess, b">", S::AngleDone);
        set(&mut next, S::MaybeLess, b"<", S::ShlDone);
        set(&mut next, S::MaybeGreater, b"=", S::GreaterEqualDone);
        set(&mut next, S::MaybeGreater, b">", S::ShrDone);
        set(&mut next, S::AfterAssign, b"=", S::EqEqDone);
        set(&mut next, S::AfterBang, b"=", S::NotEqualDone);
        set(&mut next, S::MaybeAnd, b"&", S::AndAndDone);
        set(&mut next, S::MaybeAnd, b"=", S::AmpAssignDone);
        set(&mut next, S::MaybeOr, b"|", S::OrOrDone);
        set(&mut next, S::MaybeOr, b"=", S::PipeAssignDone);
        set(&mut next, S::AfterPlus, b"=", S::PlusAssignDone);
        set(&mut next, S::AfterMinus, b"=", S::MinusAssignDone);
        set(&mut next, S::AfterStar, b"=", S::StarAssignDone);
        set(&mut next, S::AfterPercent, b"=", S::PercentAssignDone);
        set(&mut next, S::AfterCaret, b"=", S::CaretAssignDone);
        set(&mut next, S::AfterPlus, b"+", S::IncDone);
        set(&mut next, S::AfterMinus, b"-", S::DecDone);
        set(&mut next, S::ShlDone, b"=", S::ShlAssignDone);
        set(&mut next, S::ShrDone, b"=", S::ShrAssignDone);

        // Floats and dot handling
        for b in b'0'..=b'9' { next[S::MaybeDot.idx()][b as usize] = Next { state: S::FloatFrac.idx() as u16, emit: false }; }
        for b in b'0'..=b'9' { next[S::FloatDot.idx()][b as usize] = Next { state: S::FloatFrac.idx() as u16, emit: false }; }
        for b in b'0'..=b'9' { next[S::FloatFrac.idx()][b as usize] = Next { state: S::FloatFrac.idx() as u16, emit: false }; }
        next[S::FloatFrac.idx()][b'_' as usize] = Next { state: S::FloatFracAfterUnderscore.idx() as u16, emit: false };
        for b in b'0'..=b'9' { next[S::FloatFracAfterUnderscore.idx()][b as usize] = Next { state: S::FloatFrac.idx() as u16, emit: false }; }
        next[S::FloatDot.idx()][b'e' as usize] = Next { state: S::MaybeExpFromFloat.idx() as u16, emit: false };
        next[S::FloatDot.idx()][b'E' as usize] = Next { state: S::MaybeExpFromFloat.idx() as u16, emit: false };
        next[S::FloatFrac.idx()][b'e' as usize] = Next { state: S::MaybeExpFromFloat.idx() as u16, emit: false };
        next[S::FloatFrac.idx()][b'E' as usize] = Next { state: S::MaybeExpFromFloat.idx() as u16, emit: false };
        next[S::MaybeExpFromInt.idx()][b'+' as usize] = Next { state: S::FloatExpSign.idx() as u16, emit: false };
        next[S::MaybeExpFromInt.idx()][b'-' as usize] = Next { state: S::FloatExpSign.idx() as u16, emit: false };
        next[S::MaybeExpFromFloat.idx()][b'+' as usize] = Next { state: S::FloatExpSign.idx() as u16, emit: false };
        next[S::MaybeExpFromFloat.idx()][b'-' as usize] = Next { state: S::FloatExpSign.idx() as u16, emit: false };
        for b in b'0'..=b'9' { next[S::MaybeExpFromInt.idx()][b as usize] = Next { state: S::FloatExp.idx() as u16, emit: false }; }
        for b in b'0'..=b'9' { next[S::MaybeExpFromFloat.idx()][b as usize] = Next { state: S::FloatExp.idx() as u16, emit: false }; }
        for b in b'0'..=b'9' { next[S::FloatExpSign.idx()][b as usize] = Next { state: S::FloatExp.idx() as u16, emit: false }; }
        for b in b'0'..=b'9' { next[S::FloatExp.idx()][b as usize] = Next { state: S::FloatExp.idx() as u16, emit: false }; }
        next[S::FloatExp.idx()][b'_' as usize] = Next { state: S::FloatExpAfterUnderscore.idx() as u16, emit: false };
        for b in b'0'..=b'9' { next[S::FloatExpAfterUnderscore.idx()][b as usize] = Next { state: S::FloatExp.idx() as u16, emit: false }; }

        // Strings
        // InString: loop on any byte except backslash, quote, newline
        for b in 0u8..=255u8 {
            match b {
                b'\\' | b'"' | b'\n' => {}
                _ => {
                    next[S::InString.idx()][b as usize] = Next { state: S::InString.idx() as u16, emit: false };
                }
            }
        }
        next[S::InString.idx()][b'\\' as usize] = Next { state: S::StringEscape.idx() as u16, emit: false };
        next[S::InString.idx()][b'"' as usize] = Next { state: S::StringDone.idx() as u16, emit: false };
        // Escape: accept any char and return to body
        for b in 0u8..=255u8 {
            next[S::StringEscape.idx()][b as usize] = Next { state: S::InString.idx() as u16, emit: false };
        }

        // Chars
        for b in 0u8..=255u8 {
            match b {
                b'\\' | b'\'' | b'\n' => {}
                _ => {
                    next[S::InChar.idx()][b as usize] = Next { state: S::InChar.idx() as u16, emit: false };
                }
            }
        }
        next[S::InChar.idx()][b'\\' as usize] = Next { state: S::CharEscape.idx() as u16, emit: false };
        next[S::InChar.idx()][b'\'' as usize] = Next { state: S::CharDone.idx() as u16, emit: false };
        for b in 0u8..=255u8 { next[S::CharEscape.idx()][b as usize] = Next { state: S::InChar.idx() as u16, emit: false }; }

        // Streaming transform: copy Start edges to accepting states as emitting edges
        let mut token_map = [INVALID_TOKEN; N_STATES];
        for s in ALL_STATES {
            if let Some(tk) = token_of_state(*s) {
                token_map[s.idx()] = tk as u32;
                for b in 0u8..=255 {
                    let here = next[s.idx()][b as usize];
                    let has_explicit =
                        here.state != S::Reject.idx() as u16 || matches!(s, S::Reject);
                    if !has_explicit {
                        let start_edge = next[S::Start.idx()][b as usize];
                        next[s.idx()][b as usize] = Next {
                            state: start_edge.state,
                            emit: true,
                        };
                    }
                }
            }
        }

        // Reject self-loop (never emits)
        for b in 0u8..=255 {
            next[S::Reject.idx()][b as usize] = Next {
                state: S::Reject.idx() as u16,
                emit: false,
            };
        }

        Self {
            next,
            token_map,
            start: START.idx() as u16,
            reject: REJECT.idx() as u16,
        }
    }
}
