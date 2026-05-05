// src/lexer/cpu.rs
// Simple streaming-DFA lexer on CPU used as a correctness oracle for the GPU path.

use crate::lexer::tables::{
    dfa::{S, StreamingDfa},
    tokens::TokenKind,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CpuToken {
    pub kind: TokenKind,
    pub start: usize,
    pub len: usize,
}

fn ends_primary(k: TokenKind) -> bool {
    use TokenKind::*;
    matches!(
        k,
        Ident
            | Int
            | Float
            | String
            | Char
            | RParen
            | GroupRParen
            | CallRParen
            | RBracket
            | ArrayRBracket
            | IndexRBracket
            | RBrace
            | AngleGeneric
    )
}

pub fn retag_calls_and_arrays_in_place(kinds: &mut [TokenKind]) {
    use TokenKind::*;
    let mut prev_sig: Option<TokenKind> = None; // after filtering, all are significant

    for k in kinds.iter_mut() {
        let prev_ends = prev_sig.map(ends_primary).unwrap_or(false);

        match *k {
            LParen => {
                *k = if prev_ends { CallLParen } else { GroupLParen };
            }
            LBracket => {
                *k = if prev_ends {
                    IndexLBracket
                } else {
                    ArrayLBracket
                };
            }
            Plus => {
                *k = if prev_ends { InfixPlus } else { PrefixPlus };
            }
            Minus => {
                *k = if prev_ends { InfixMinus } else { PrefixMinus };
            }
            _ => {}
        }

        prev_sig = Some(*k);
    }

    retag_closes_by_layer_rank(kinds);
}

fn keyword_kind(bytes: &[u8]) -> Option<TokenKind> {
    match bytes {
        b"pub" => Some(TokenKind::Pub),
        b"fn" => Some(TokenKind::Fn),
        b"let" => Some(TokenKind::Let),
        b"return" => Some(TokenKind::Return),
        b"if" => Some(TokenKind::If),
        b"else" => Some(TokenKind::Else),
        b"while" => Some(TokenKind::While),
        b"break" => Some(TokenKind::Break),
        b"continue" => Some(TokenKind::Continue),
        _ => None,
    }
}

fn retag_keywords_in_place(tokens: &mut [CpuToken], src: &[u8]) {
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

fn retag_closes_by_layer_rank(kinds: &mut [TokenKind]) {
    let n_layers = kinds.len().saturating_add(2);
    let mut pushes_by_layer = vec![Vec::<usize>::new(); n_layers];
    let mut pops_by_layer = vec![Vec::<usize>::new(); n_layers];
    let mut depth = 0i32;

    for (i, &kind) in kinds.iter().enumerate() {
        if is_open(kind) {
            let layer = depth + 1;
            if layer >= 0 {
                let layer = layer as usize;
                if layer < n_layers {
                    pushes_by_layer[layer].push(i);
                }
            }
            depth += 1;
        } else if is_close(kind) {
            let layer = depth;
            if layer >= 0 {
                let layer = layer as usize;
                if layer < n_layers {
                    pops_by_layer[layer].push(i);
                }
            }
            depth -= 1;
        }
    }

    for layer in 0..n_layers {
        let npairs = pushes_by_layer[layer].len().min(pops_by_layer[layer].len());
        for rank in 0..npairs {
            let open_i = pushes_by_layer[layer][rank];
            let close_i = pops_by_layer[layer][rank];
            if let Some(close_kind) = close_for_open(kinds[open_i], kinds[close_i]) {
                kinds[close_i] = close_kind;
            }
        }
    }
}

fn is_open(kind: TokenKind) -> bool {
    use TokenKind::*;
    matches!(
        kind,
        GroupLParen | CallLParen | ArrayLBracket | IndexLBracket
    )
}

fn is_close(kind: TokenKind) -> bool {
    use TokenKind::*;
    matches!(
        kind,
        RParen | RBracket | GroupRParen | CallRParen | ArrayRBracket | IndexRBracket
    )
}

fn close_for_open(open: TokenKind, close: TokenKind) -> Option<TokenKind> {
    use TokenKind::*;
    match (open, close) {
        (GroupLParen, RParen | GroupRParen | CallRParen) => Some(GroupRParen),
        (CallLParen, RParen | GroupRParen | CallRParen) => Some(CallRParen),
        (ArrayLBracket, RBracket | ArrayRBracket | IndexRBracket) => Some(ArrayRBracket),
        (IndexLBracket, RBracket | ArrayRBracket | IndexRBracket) => Some(IndexRBracket),
        _ => None,
    }
}

#[inline]
fn keep_kind(k: TokenKind) -> bool {
    use TokenKind::*;
    !matches!(k, White | LineComment | BlockComment)
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
                '·'
            },
        );
    }
    (lo, s)
}

/// Deterministic CPU lexer that mirrors the streaming-emit rules used on GPU.
/// Returns kept tokens (whitespace/comments filtered out).
pub fn lex_on_cpu(input: &str) -> Result<Vec<CpuToken>, String> {
    let bytes = input.as_bytes();
    let n = bytes.len();

    let dfa = StreamingDfa::new();
    let mut out: Vec<CpuToken> = Vec::new();

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
            if kind_u32 == u32::MAX {
                return Err(format!("emit from non-accepting state={state} at i={i}"));
            }
            let kind = unsafe { std::mem::transmute::<u32, TokenKind>(kind_u32) };
            if keep_kind(kind) {
                out.push(CpuToken {
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
    if end_kind_u32 != u32::MAX {
        let kind = unsafe { std::mem::transmute::<u32, TokenKind>(end_kind_u32) };
        if keep_kind(kind) {
            out.push(CpuToken {
                kind,
                start: tok_start,
                len: n - tok_start,
            });
        }
        {
            retag_keywords_in_place(&mut out, bytes);
            let mut kinds: Vec<TokenKind> = out.iter().map(|t| t.kind).collect();
            retag_calls_and_arrays_in_place(&mut kinds);
            for (tok, k) in out.iter_mut().zip(kinds.into_iter()) {
                tok.kind = k;
            }
        }
        return Ok(out);
    }

    // If we got here and are in REJECT, tell the user where we last were OK.
    if state == S::Reject.idx() {
        return Err("ended in REJECT".into());
    }

    // Non-accepting but not reject (e.g., unterminated block comment) — surface it clearly.
    Err(format!(
        "ended in non-accepting state={state} (unterminated token?)"
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(src: &str) -> Vec<TokenKind> {
        lex_on_cpu(src)
            .expect("lex")
            .into_iter()
            .map(|token| token.kind)
            .collect()
    }

    #[test]
    fn retags_prefix_and_infix_plus_minus() {
        use TokenKind::*;

        assert_eq!(
            kinds("-a + +b - c"),
            vec![
                PrefixMinus,
                Ident,
                InfixPlus,
                PrefixPlus,
                Ident,
                InfixMinus,
                Ident
            ]
        );
    }

    #[test]
    fn retags_calls_groups_arrays_and_indexes() {
        use TokenKind::*;

        assert_eq!(
            kinds("f(a)[b] + [c]"),
            vec![
                Ident,
                CallLParen,
                Ident,
                CallRParen,
                IndexLBracket,
                Ident,
                IndexRBracket,
                InfixPlus,
                ArrayLBracket,
                Ident,
                ArrayRBracket
            ]
        );
    }

    #[test]
    fn retags_closes_from_matched_openers() {
        use TokenKind::*;

        assert_eq!(
            kinds("(a) f(b)[c] + [d]"),
            vec![
                GroupLParen,
                Ident,
                GroupRParen,
                Ident,
                CallLParen,
                Ident,
                CallRParen,
                IndexLBracket,
                Ident,
                IndexRBracket,
                InfixPlus,
                ArrayLBracket,
                Ident,
                ArrayRBracket
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
                Pub,
                Fn,
                Ident,
                CallLParen,
                CallRParen,
                LBrace,
                Let,
                Ident,
                Assign,
                Int,
                Semicolon,
                If,
                GroupLParen,
                Ident,
                GroupRParen,
                LBrace,
                Return,
                Ident,
                Semicolon,
                RBrace,
                Else,
                LBrace,
                While,
                GroupLParen,
                Ident,
                GroupRParen,
                LBrace,
                Break,
                Semicolon,
                Continue,
                Semicolon,
                RBrace,
                RBrace,
                RBrace
            ]
        );
    }
}
