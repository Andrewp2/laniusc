//! TEST-ONLY CPU lexer oracle.
//!
//! This module is not a compiler implementation and must not be used as a
//! fallback. It exists so tests and fuzzers can compare GPU lexer output against
//! a small host-side oracle while the production compiler lexes on the GPU.

use crate::lexer::tables::{
    dfa::{S, StreamingDfa},
    tokens::{INVALID_TOKEN, TokenKind},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Token record produced by the CPU lexer oracle used in tests.
pub struct TestCpuToken {
    /// Token kind after lexer-owned keyword/range repairs.
    pub kind: TokenKind,
    /// Start byte offset.
    pub start: usize,
    /// Token byte length.
    pub len: usize,
}

fn keyword_kind(bytes: &[u8]) -> Option<TokenKind> {
    match bytes {
        b"pub" => Some(TokenKind::Pub),
        b"fn" => Some(TokenKind::Fn),
        b"in" => Some(TokenKind::In),
        b"let" => Some(TokenKind::Let),
        b"for" => Some(TokenKind::For),
        b"return" => Some(TokenKind::Return),
        b"if" => Some(TokenKind::If),
        b"else" => Some(TokenKind::Else),
        b"while" => Some(TokenKind::While),
        b"break" => Some(TokenKind::Break),
        b"continue" => Some(TokenKind::Continue),
        b"true" => Some(TokenKind::True),
        b"false" => Some(TokenKind::False),
        b"const" => Some(TokenKind::Const),
        b"enum" => Some(TokenKind::Enum),
        b"extern" => Some(TokenKind::Extern),
        b"import" => Some(TokenKind::Import),
        b"impl" => Some(TokenKind::Impl),
        b"match" => Some(TokenKind::Match),
        b"module" => Some(TokenKind::Module),
        b"self" => Some(TokenKind::SelfValue),
        b"struct" => Some(TokenKind::Struct),
        b"trait" => Some(TokenKind::Trait),
        b"type" => Some(TokenKind::Type),
        b"where" => Some(TokenKind::Where),
        _ => None,
    }
}

fn retag_keywords_in_place(tokens: &mut [TestCpuToken], src: &[u8]) {
    for token in tokens {
        if token.kind != TokenKind::Ident {
            continue;
        }
        let start = token.start;
        let end = start.saturating_add(token.len);
        if end <= src.len()
            && let Some(kind) = keyword_kind(&src[start..end])
        {
            token.kind = kind;
        }
    }
}

fn repair_numeric_dotdot_ranges(tokens: &mut Vec<TestCpuToken>, src: &[u8]) {
    let mut i = 0;
    while i + 1 < tokens.len() {
        let current = tokens[i];
        let next = tokens[i + 1];
        if current.kind != TokenKind::Float
            || current.len < 2
            || next.kind != TokenKind::Dot
            || next.len != 1
            || next.start != current.start + current.len
        {
            i += 1;
            continue;
        }

        let dot = current.start + current.len - 1;
        if src.get(dot) != Some(&b'.') {
            i += 1;
            continue;
        }

        tokens[i].kind = TokenKind::Int;
        tokens[i].len -= 1;
        tokens[i + 1].kind = TokenKind::DotDot;
        tokens[i + 1].start -= 1;
        tokens[i + 1].len += 1;
        i += 2;
    }
}

fn retag_inclusive_dotdot_ranges(tokens: &mut [TestCpuToken]) {
    for i in 0..tokens.len().saturating_sub(1) {
        let current = tokens[i];
        let next = tokens[i + 1];
        if current.kind == TokenKind::DotDot
            && next.kind == TokenKind::Assign
            && next.start == current.start + current.len
        {
            tokens[i].kind = TokenKind::DotDotEqual;
        }
    }
}

#[inline]
fn keep_kind(k: TokenKind) -> bool {
    use TokenKind::*;
    !matches!(k, White | LineComment | BlockComment)
}

fn decode_dfa_token(kind_u32: u32, state: usize, at: usize) -> Result<TokenKind, String> {
    TokenKind::from_u32(kind_u32).ok_or_else(|| {
        if kind_u32 == INVALID_TOKEN {
            format!("emit from non-accepting state={state} at i={at}")
        } else {
            format!("invalid token kind {kind_u32} from DFA state={state} at i={at}")
        }
    })
}

fn slice_dbg(src: &[u8], i: usize) -> (usize, String) {
    let lo = i.saturating_sub(16);
    let hi = (i + 16).min(src.len());
    let mut s = String::new();
    for &b in &src[lo..hi] {
        s.push(
            if b.is_ascii_graphic() || b == b' ' || b == b'\n' || b == b'\t' || b == b'\r' {
                b as char
            } else {
                '.'
            },
        );
    }
    (lo, s)
}

fn lex_raw_kept(input: &str) -> Result<Vec<TestCpuToken>, String> {
    let bytes = input.as_bytes();
    let n = bytes.len();

    if n == 0 {
        return Ok(Vec::new());
    }

    let dfa = StreamingDfa::new();
    let mut out: Vec<TestCpuToken> = Vec::new();

    let mut state = dfa.start as usize;
    let mut tok_start: usize = 0;

    for i in 0..n {
        let b = bytes[i];
        let next = dfa.next[state][b as usize];

        // Reject as-soon-as we see it; include a little context.
        if next.state as usize == S::Reject.idx() {
            let (ctx_lo, ctx) = slice_dbg(bytes, i);
            return Err(format!(
                "fell into REJECT at byte {i} (char {:?}, 0x{:02X}) from state={state}; \
                 context [{}..{}):\n{}",
                b as char,
                b,
                ctx_lo,
                ctx_lo + ctx.len(),
                ctx
            ));
        }

        // If this edge "emits", a token just ended BEFORE consuming b.
        if next.emit {
            let kind_u32 = dfa.token_map[state];
            let kind = decode_dfa_token(kind_u32, state, i)?;
            if keep_kind(kind) {
                out.push(TestCpuToken {
                    kind,
                    start: tok_start,
                    len: i - tok_start,
                });
            }
            // The emitting edge already transitions as if we consumed `b`,
            // so the next token starts at `i`.
            tok_start = i;
        }

        state = next.state as usize;
    }

    // End-of-input: if final state is accepting, emit the final token to `n`.
    let end_kind_u32 = dfa.token_map[state];
    if end_kind_u32 != INVALID_TOKEN {
        let kind = decode_dfa_token(end_kind_u32, state, n)?;
        if keep_kind(kind) {
            out.push(TestCpuToken {
                kind,
                start: tok_start,
                len: n - tok_start,
            });
        }
        return Ok(out);
    }

    // If we got here and are in REJECT, tell the user where we last were OK.
    if state == S::Reject.idx() {
        return Err("ended in REJECT".into());
    }

    // Non-accepting but not reject (e.g., unterminated block comment): surface it clearly.
    Err(format!(
        "ended in non-accepting state={state} (unterminated token?)"
    ))
}

/// Deterministic test CPU oracle for GPU lexer readback.
/// Returns kept DFA tokens with lexer-owned keyword retags applied.
pub fn lex_on_test_cpu(input: &str) -> Result<Vec<TestCpuToken>, String> {
    let bytes = input.as_bytes();
    let mut out = lex_raw_kept(input)?;
    repair_numeric_dotdot_ranges(&mut out, bytes);
    retag_inclusive_dotdot_ranges(&mut out);
    retag_keywords_in_place(&mut out, bytes);
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(src: &str) -> Vec<TokenKind> {
        lex_on_test_cpu(src)
            .expect("lex")
            .into_iter()
            .map(|token| token.kind)
            .collect()
    }

    #[test]
    fn lexes_empty_input_as_empty_stream() {
        assert_eq!(lex_on_test_cpu("").expect("lex empty input"), Vec::new());
    }

    #[test]
    fn keeps_plus_and_minus_raw_at_lexer_boundary() {
        use TokenKind::*;

        assert_eq!(
            kinds("-a + +b - c"),
            vec![Minus, Ident, Plus, Plus, Ident, Minus, Ident]
        );
    }

    #[test]
    fn keeps_delimiters_raw_at_lexer_boundary() {
        use TokenKind::*;

        assert_eq!(
            kinds("f(a)[b] + [c]"),
            vec![
                Ident, LParen, Ident, RParen, LBracket, Ident, RBracket, Plus, LBracket, Ident,
                RBracket
            ]
        );
    }

    #[test]
    fn keeps_close_delimiters_raw_at_lexer_boundary() {
        use TokenKind::*;

        assert_eq!(
            kinds("(a) f(b)[c] + [d]"),
            vec![
                LParen, Ident, RParen, Ident, LParen, Ident, RParen, LBracket, Ident, RBracket,
                Plus, LBracket, Ident, RBracket
            ]
        );
    }

    #[test]
    fn retags_keywords_from_ident_lexemes() {
        use TokenKind::*;

        assert_eq!(
            kinds(
                "pub fn f() { let x = 1; if (x) { return x; } else { while (x) { break; continue; } } }"
            ),
            vec![
                Pub, Fn, Ident, LParen, RParen, LBrace, Let, Ident, Assign, Int, Semicolon, If,
                LParen, Ident, RParen, LBrace, Return, Ident, Semicolon, RBrace, Else, LBrace,
                While, LParen, Ident, RParen, LBrace, Break, Semicolon, Continue, Semicolon,
                RBrace, RBrace, RBrace
            ]
        );
    }

    #[test]
    fn qualified_module_and_import_paths_are_raw_identifier_segments() {
        use TokenKind::*;

        assert_eq!(
            kinds("module app::main;\nimport core::f32;"),
            vec![
                Module, Ident, Colon, Colon, Ident, Semicolon, Import, Ident, Colon, Colon, Ident,
                Semicolon
            ]
        );
    }

    #[test]
    fn qualified_type_paths_are_raw_identifier_segments() {
        use TokenKind::*;

        assert_eq!(
            kinds("let value: core::f32 = 0.0;"),
            vec![
                Let, Ident, Colon, Ident, Colon, Colon, Ident, Assign, Float, Semicolon
            ]
        );
    }

    #[test]
    fn lexes_numeric_exclusive_ranges_without_stealing_float_literals() {
        use TokenKind::*;

        assert_eq!(
            kinds("0..samples 1.0 1. .5 ..rest 1..=end"),
            vec![
                Int,
                DotDot,
                Ident,
                Float,
                Float,
                Float,
                DotDot,
                Ident,
                Int,
                DotDotEqual,
                Assign,
                Ident
            ]
        );
    }
}
