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
    matches!(k, Ident | Int | String | RParen | RBracket | RBrace)
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
            _ => {}
        }

        prev_sig = Some(*k);
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
