// src/lexer/tables/dfa.rs
use super::tokens::{INVALID_TOKEN, TokenKind};

// DFA states (small hand-built DFA).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum S {
    Start,
    Ident,
    Int,
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

    MaybeGreater,
    GreaterEqualDone,

    MaybeAnd,
    AndAndDone,

    MaybeOr,
    OrOrDone,

    EqEqDone,

    Reject,
}
impl S {
    #[inline]
    pub fn idx(self) -> usize {
        self as usize
    }
}

pub const N_STATES: usize = 32;
pub const START: S = S::Start;
pub const REJECT: S = S::Reject;

const ALL_STATES: &[S] = &[
    S::Start,
    S::Ident,
    S::Int,
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
    S::AfterBang,
    S::AfterLBracket,
    S::AfterRBracket,
    S::AfterLBrace,
    S::AfterRBrace,
    S::MaybeLess,
    S::LessEqualDone,
    S::AngleDone,
    S::MaybeGreater,
    S::GreaterEqualDone,
    S::MaybeAnd,
    S::AndAndDone,
    S::MaybeOr,
    S::OrOrDone,
    S::EqEqDone,
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
        White => Some(TokenKind::White),
        MaybeSlash => Some(TokenKind::Slash),
        BlockDone => Some(TokenKind::BlockComment),
        AfterLParen => Some(TokenKind::LParen),
        AfterRParen => Some(TokenKind::RParen),
        AfterPlus => Some(TokenKind::Plus),
        AfterStar => Some(TokenKind::Star),
        AfterAssign => Some(TokenKind::Assign),
        AfterMinus => Some(TokenKind::Minus), // <--- NEW
        LineComment => Some(TokenKind::LineComment),

        AfterBang => Some(TokenKind::Not),
        AfterLBracket => Some(TokenKind::LBracket),
        AfterRBracket => Some(TokenKind::RBracket),
        AfterLBrace => Some(TokenKind::LBrace),
        AfterRBrace => Some(TokenKind::RBrace),

        MaybeLess => Some(TokenKind::Lt),
        LessEqualDone => Some(TokenKind::Le),
        AngleDone => Some(TokenKind::AngleGeneric),
        MaybeGreater => Some(TokenKind::Gt),
        GreaterEqualDone => Some(TokenKind::Ge),

        EqEqDone => Some(TokenKind::EqEq),
        MaybeAnd => Some(TokenKind::Ampersand),
        AndAndDone => Some(TokenKind::AndAnd),
        MaybeOr => Some(TokenKind::Pipe),
        OrOrDone => Some(TokenKind::OrOr),
        _ => None,
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
                S::Int
            } else if is_white(b) {
                S::White
            } else {
                match b {
                    b'(' => S::AfterLParen,
                    b')' => S::AfterRParen,
                    b'+' => S::AfterPlus,
                    b'*' => S::AfterStar,
                    b'=' => S::AfterAssign,
                    b'-' => S::AfterMinus, // <--- NEW
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
                    _ => S::Reject,
                }
            };
            next[S::Start.idx()][b as usize] = Next {
                state: to.idx() as u16,
                emit: false,
            };
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

        // Int
        for b in b'0'..=b'9' {
            next[S::Int.idx()][b as usize] = Next {
                state: S::Int.idx() as u16,
                emit: false,
            };
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
        set(&mut next, S::MaybeGreater, b"=", S::GreaterEqualDone);
        set(&mut next, S::AfterAssign, b"=", S::EqEqDone);
        set(&mut next, S::MaybeAnd, b"&", S::AndAndDone);
        set(&mut next, S::MaybeOr, b"|", S::OrOrDone);

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
