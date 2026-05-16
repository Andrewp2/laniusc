// src/parser/tables.rs
// Offline precomputed tables for the LLP parser, matching the VM07 layout.
//
// We keep the existing MVP action-header helpers for the current demo,
// and add the full "3 data structures / 7 arrays" used by the real parser.
//
// Arrays produced offline:
//   1) Stack changes (supersequence)                 : sc_superseq[u32]
//      Offsets, lengths per (prev_kind, this_kind)   : sc_off[u32], sc_len[u32]
//      Encoding: push(2*x+1), pop(2*x), where x = stack symbol id.
//   2) Partial parse (supersequence)                 : pp_superseq[u32]
//      Offsets, lengths per (prev_kind, this_kind)   : pp_off[u32], pp_len[u32]
//      Elements are production IDs.
//   3) Production arity                              : prod_arity[u32] (by production ID)
//
// File I/O (compact, little-endian) uses magic "LXPRSE02".

use std::{fs, io::Write, path::Path};

use crate::{lexer::tables::tokens::TokenKind, parser::buffers::ActionHeader};

// ---------- MVP (already in tree): action headers for bracket sanity ----------

/// Returns a zeroed action table of size (n_kinds * n_kinds) * sizeof(ActionHeader).
pub fn build_dummy_action_table(n_kinds: u32) -> Vec<u8> {
    let n = (n_kinds as usize) * (n_kinds as usize);
    vec![0u8; n * std::mem::size_of::<ActionHeader>()]
}

/// Very small MVP table:
/// - For any prev kind, if `this` is an opening delimiter, record a 1-element push with a tag.
/// - For any prev kind, if `this` is a closing delimiter, record a 1-element pop (generic tag=0).
///
/// This is enough to verify the llp_pairs kernel + readback path end-to-end.
pub fn build_bracket_action_table(n_kinds: u32) -> Vec<u8> {
    let mut bytes = build_dummy_action_table(n_kinds);
    let sz = std::mem::size_of::<ActionHeader>();

    // Tags (arbitrary small integers for the MVP)
    const TAG_GROUP_PAREN: u32 = 1;
    const TAG_CALL_PAREN: u32 = 2;
    const TAG_ARRAY_BRACK: u32 = 3;
    const TAG_INDEX_BRACK: u32 = 4;
    const TAG_PARAM_PAREN: u32 = 5;
    const TAG_TYPE_ARRAY_BRACK: u32 = 6;

    // Helper: write header into (prev, this) cell.
    let mut set = |prev: u32, this: u32, h: ActionHeader| {
        let idx = (prev as usize) * (n_kinds as usize) + (this as usize);
        let off = idx * sz;
        bytes[off..off + 4].copy_from_slice(&h.push_len.to_le_bytes());
        bytes[off + 4..off + 8].copy_from_slice(&h.emit_len.to_le_bytes());
        bytes[off + 8..off + 12].copy_from_slice(&h.pop_tag.to_le_bytes());
        bytes[off + 12..off + 16].copy_from_slice(&h.pop_count.to_le_bytes());
    };

    let all_prev = 0..n_kinds;

    // Push on opening tokens
    for p in all_prev.clone() {
        set(
            p,
            TokenKind::GroupLParen as u32,
            ActionHeader {
                push_len: 1,
                emit_len: 0,
                pop_tag: TAG_GROUP_PAREN,
                pop_count: 0,
            },
        );
        set(
            p,
            TokenKind::CallLParen as u32,
            ActionHeader {
                push_len: 1,
                emit_len: 0,
                pop_tag: TAG_CALL_PAREN,
                pop_count: 0,
            },
        );
        set(
            p,
            TokenKind::ParamLParen as u32,
            ActionHeader {
                push_len: 1,
                emit_len: 0,
                pop_tag: TAG_PARAM_PAREN,
                pop_count: 0,
            },
        );
        set(
            p,
            TokenKind::ArrayLBracket as u32,
            ActionHeader {
                push_len: 1,
                emit_len: 0,
                pop_tag: TAG_ARRAY_BRACK,
                pop_count: 0,
            },
        );
        set(
            p,
            TokenKind::IndexLBracket as u32,
            ActionHeader {
                push_len: 1,
                emit_len: 0,
                pop_tag: TAG_INDEX_BRACK,
                pop_count: 0,
            },
        );
        set(
            p,
            TokenKind::TypeArrayLBracket as u32,
            ActionHeader {
                push_len: 1,
                emit_len: 0,
                pop_tag: TAG_TYPE_ARRAY_BRACK,
                pop_count: 0,
            },
        );
    }

    // Pop on closing tokens (generic pop_tag=0 in MVP)
    for p in all_prev {
        for close in [
            TokenKind::RParen,
            TokenKind::GroupRParen,
            TokenKind::CallRParen,
            TokenKind::ParamRParen,
        ] {
            set(
                p,
                close as u32,
                ActionHeader {
                    push_len: 0,
                    emit_len: 0,
                    pop_tag: 0,
                    pop_count: 1,
                },
            );
        }
        for close in [
            TokenKind::RBracket,
            TokenKind::ArrayRBracket,
            TokenKind::IndexRBracket,
            TokenKind::TypeArrayRBracket,
        ] {
            set(
                p,
                close as u32,
                ActionHeader {
                    push_len: 0,
                    emit_len: 0,
                    pop_tag: 0,
                    pop_count: 1,
                },
            );
        }
        // (Add RBrace if you want block matching in the MVP)
    }

    bytes
}

// ---------- Real offline tables (3 data structures / 7 arrays) ----------

const MAGIC_V1: &[u8; 8] = b"LXPRSE01";
const MAGIC_V2: &[u8; 8] = b"LXPRSE02";
pub const INVALID_TABLE_ENTRY: u32 = u32::MAX;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Ll1ParseError {
    pub pos: usize,
    pub code: Ll1ParseErrorCode,
    pub detail: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Ll1ParseErrorCode {
    TerminalMismatch,
    NoPrediction,
    TrailingInput,
    BadSymbol,
    TablesUnavailable,
}

impl std::fmt::Display for Ll1ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "LL(1) parse error at token {}, {:?} ({})",
            self.pos, self.code, self.detail
        )
    }
}

impl std::error::Error for Ll1ParseError {}

#[inline]
pub fn encode_push(symbol_id: u32) -> u32 {
    // push = 2*x + 1
    symbol_id
        .checked_mul(2)
        .and_then(|v| v.checked_add(1))
        .expect("overflow in push encode")
}
#[inline]
pub fn encode_pop(symbol_id: u32) -> u32 {
    // pop = 2*x
    symbol_id.checked_mul(2).expect("overflow in pop encode")
}

#[derive(Debug, Clone)]
pub struct PrecomputedParseTables {
    // basic sizes
    pub n_kinds: u32,
    pub n_productions: u32,

    // 1) stack-change supersequence + 2D views (row-major by prev_kind, this_kind)
    pub sc_superseq: Vec<u32>,
    pub sc_off: Vec<u32>,    // len = n_kinds * n_kinds
    pub sc_len: Vec<u32>,    // len = n_kinds * n_kinds
    pub sc_symbol_bits: u32, // min bits required for stack symbol IDs

    // 2) partial-parse supersequence + 2D views (row-major)
    pub pp_superseq: Vec<u32>,
    pub pp_off: Vec<u32>,  // len = n_kinds * n_kinds
    pub pp_len: Vec<u32>,  // len = n_kinds * n_kinds
    pub pp_prod_bits: u32, // min bits required for production IDs

    // 3) production arity
    pub prod_arity: Vec<u32>, // len = n_productions

    // 4) Full LL(1) acceptance tables.
    // Symbol encoding for rhs streams:
    //   terminal    = token kind id in [0, n_kinds)
    //   nonterminal = n_kinds + nonterminal id
    pub n_nonterminals: u32,
    pub start_nonterminal: u32,
    pub ll1_predict: Vec<u32>, // len = n_nonterminals * n_kinds; u32::MAX means error
    pub prod_rhs_off: Vec<u32>, // len = n_productions
    pub prod_rhs_len: Vec<u32>, // len = n_productions
    pub prod_rhs: Vec<u32>,
}

impl PrecomputedParseTables {
    pub fn new(n_kinds: u32, n_productions: u32) -> Self {
        let cells = (n_kinds as usize) * (n_kinds as usize);
        Self {
            n_kinds,
            n_productions,
            sc_superseq: Vec::new(),
            sc_off: vec![0; cells],
            sc_len: vec![0; cells],
            sc_symbol_bits: 0,
            pp_superseq: Vec::new(),
            pp_off: vec![0; cells],
            pp_len: vec![0; cells],
            pp_prod_bits: 0,
            prod_arity: vec![0; n_productions as usize],
            n_nonterminals: 0,
            start_nonterminal: 0,
            ll1_predict: Vec::new(),
            prod_rhs_off: vec![0; n_productions as usize],
            prod_rhs_len: vec![0; n_productions as usize],
            prod_rhs: Vec::new(),
        }
    }

    #[inline]
    fn cell_index(&self, prev: u32, this: u32) -> usize {
        (prev as usize) * (self.n_kinds as usize) + (this as usize)
    }

    /// Append a stack-change sequence for a given (prev,this) token-kind pair.
    pub fn set_sc_for_pair(&mut self, prev: u32, this: u32, seq: &[u32]) {
        let idx = self.cell_index(prev, this);
        let off = self.sc_superseq.len() as u32;
        self.sc_off[idx] = off;
        self.sc_len[idx] = seq.len() as u32;
        self.sc_superseq.extend_from_slice(seq);
    }

    /// Append a partial-parse sequence (production IDs) for a given (prev,this).
    pub fn set_pp_for_pair(&mut self, prev: u32, this: u32, seq: &[u32]) {
        let idx = self.cell_index(prev, this);
        let off = self.pp_superseq.len() as u32;
        self.pp_off[idx] = off;
        self.pp_len[idx] = seq.len() as u32;
        self.pp_superseq.extend_from_slice(seq);
    }

    pub fn finalize_bit_widths(&mut self, max_symbol_id: u32) {
        // ceil(log2(max+1)) as a tiny helper
        fn bits_for(x: u32) -> u32 {
            let mut v = x;
            let mut bits = 0;
            while v > 0 {
                v >>= 1;
                bits += 1;
            }
            bits.max(1)
        }
        self.sc_symbol_bits = bits_for(max_symbol_id);
        self.pp_prod_bits = {
            let max_prod = self.n_productions.saturating_sub(1);
            if max_prod == 0 {
                1
            } else {
                let mut v = max_prod;
                let mut b = 0;
                while v > 0 {
                    v >>= 1;
                    b += 1;
                }
                b
            }
        };
    }

    /// Test-only host LL(1) oracle for parser tests and fuzz tooling.
    ///
    /// The compiler must not call this; production parsing is recorded and
    /// executed by the parser driver.
    pub fn test_cpu_ll1_production_stream(
        &self,
        token_kinds: &[u32],
    ) -> Result<Vec<u32>, Ll1ParseError> {
        let (productions, _) = self.test_cpu_ll1_production_stream_with_positions(token_kinds)?;
        Ok(productions)
    }

    pub fn test_cpu_ll1_production_stream_with_positions(
        &self,
        token_kinds: &[u32],
    ) -> Result<(Vec<u32>, Vec<u32>), Ll1ParseError> {
        if self.n_nonterminals == 0 || self.ll1_predict.is_empty() {
            return Err(Ll1ParseError {
                pos: 0,
                code: Ll1ParseErrorCode::TablesUnavailable,
                detail: 0,
            });
        }

        let input_end = token_kinds.len().saturating_sub(1);
        let first_input = if token_kinds.first().copied() == Some(0) {
            1
        } else {
            0
        };
        let mut pos = first_input;
        let mut stack = vec![self.n_kinds + self.start_nonterminal];
        let mut out = Vec::new();
        let mut positions = Vec::new();

        while let Some(sym) = stack.pop() {
            let lookahead = if pos < input_end { token_kinds[pos] } else { 0 };

            if sym < self.n_kinds {
                if sym != lookahead {
                    return Err(Ll1ParseError {
                        pos,
                        code: Ll1ParseErrorCode::TerminalMismatch,
                        detail: sym,
                    });
                }
                pos += 1;
                continue;
            }

            let nt = sym - self.n_kinds;
            if nt >= self.n_nonterminals || lookahead >= self.n_kinds {
                return Err(Ll1ParseError {
                    pos,
                    code: Ll1ParseErrorCode::BadSymbol,
                    detail: sym,
                });
            }

            let pred_idx = (nt as usize) * (self.n_kinds as usize) + lookahead as usize;
            let prod = self.ll1_predict[pred_idx];
            if prod == INVALID_TABLE_ENTRY || prod >= self.n_productions {
                return Err(Ll1ParseError {
                    pos,
                    code: Ll1ParseErrorCode::NoPrediction,
                    detail: nt,
                });
            }

            out.push(prod);
            positions.push(pos.saturating_sub(first_input) as u32);
            let off = self.prod_rhs_off[prod as usize] as usize;
            let len = self.prod_rhs_len[prod as usize] as usize;
            stack.extend(self.prod_rhs[off..off + len].iter().rev().copied());
        }

        if pos != input_end {
            return Err(Ll1ParseError {
                pos,
                code: Ll1ParseErrorCode::TrailingInput,
                detail: token_kinds.get(pos).copied().unwrap_or(0),
            });
        }

        Ok((out, positions))
    }

    /// Test-only host oracle for the pair-projected production stream.
    pub fn test_cpu_projected_production_stream(&self, token_kinds: &[u32]) -> Vec<u32> {
        let mut out = Vec::new();
        for pair in token_kinds.windows(2) {
            let prev = pair[0];
            let this = pair[1];
            if prev >= self.n_kinds || this >= self.n_kinds {
                continue;
            }
            let idx = self.cell_index(prev, this);
            let off = self.pp_off[idx] as usize;
            let len = self.pp_len[idx] as usize;
            out.extend_from_slice(&self.pp_superseq[off..off + len]);
        }
        out
    }

    // ---------- Binary I/O ----------

    pub fn save_bin<P: AsRef<Path>>(&self, path: P) -> std::io::Result<()> {
        let mut f = fs::File::create(path)?;
        f.write_all(MAGIC_V2)?;
        f.write_all(&self.n_kinds.to_le_bytes())?;
        f.write_all(&self.n_productions.to_le_bytes())?;
        f.write_all(&self.sc_symbol_bits.to_le_bytes())?;
        f.write_all(&self.pp_prod_bits.to_le_bytes())?;

        // helper to write a Vec<u32>
        fn write_vec(f: &mut fs::File, v: &Vec<u32>) -> std::io::Result<()> {
            let len = v.len() as u32;
            f.write_all(&len.to_le_bytes())?;
            for &x in v {
                f.write_all(&x.to_le_bytes())?;
            }
            Ok(())
        }

        write_vec(&mut f, &self.sc_superseq)?;
        write_vec(&mut f, &self.sc_off)?;
        write_vec(&mut f, &self.sc_len)?;
        write_vec(&mut f, &self.pp_superseq)?;
        write_vec(&mut f, &self.pp_off)?;
        write_vec(&mut f, &self.pp_len)?;
        write_vec(&mut f, &self.prod_arity)?;
        f.write_all(&self.n_nonterminals.to_le_bytes())?;
        f.write_all(&self.start_nonterminal.to_le_bytes())?;
        write_vec(&mut f, &self.ll1_predict)?;
        write_vec(&mut f, &self.prod_rhs_off)?;
        write_vec(&mut f, &self.prod_rhs_len)?;
        write_vec(&mut f, &self.prod_rhs)?;
        Ok(())
    }

    pub fn load_bin_bytes(mut data: &[u8]) -> Result<Self, String> {
        fn take<const N: usize>(buf: &mut &[u8]) -> Result<[u8; N], String> {
            if buf.len() < N {
                return Err("truncated parse tables".into());
            }
            let mut out = [0u8; N];
            out.copy_from_slice(&buf[..N]);
            *buf = &buf[N..];
            Ok(out)
        }
        fn take_u32(buf: &mut &[u8]) -> Result<u32, String> {
            let le = take::<4>(buf)?;
            Ok(u32::from_le_bytes(le))
        }
        fn take_vec(buf: &mut &[u8]) -> Result<Vec<u32>, String> {
            let len = take_u32(buf)? as usize;
            let mut v = Vec::with_capacity(len);
            for _ in 0..len {
                v.push(take_u32(buf)?);
            }
            Ok(v)
        }

        // header
        let magic = take::<8>(&mut data)?;
        if &magic != MAGIC_V1 && &magic != MAGIC_V2 {
            return Err("bad magic in parse tables .bin".into());
        }
        let is_v2 = &magic == MAGIC_V2;
        let n_kinds = take_u32(&mut data)?;
        let n_productions = take_u32(&mut data)?;
        let sc_symbol_bits = take_u32(&mut data)?;
        let pp_prod_bits = take_u32(&mut data)?;

        let sc_superseq = take_vec(&mut data)?;
        let sc_off = take_vec(&mut data)?;
        let sc_len = take_vec(&mut data)?;
        let pp_superseq = take_vec(&mut data)?;
        let pp_off = take_vec(&mut data)?;
        let pp_len = take_vec(&mut data)?;
        let prod_arity = take_vec(&mut data)?;
        let (n_nonterminals, start_nonterminal, ll1_predict, prod_rhs_off, prod_rhs_len, prod_rhs) =
            if is_v2 {
                (
                    take_u32(&mut data)?,
                    take_u32(&mut data)?,
                    take_vec(&mut data)?,
                    take_vec(&mut data)?,
                    take_vec(&mut data)?,
                    take_vec(&mut data)?,
                )
            } else {
                (
                    0,
                    0,
                    Vec::new(),
                    vec![0; n_productions as usize],
                    vec![0; n_productions as usize],
                    Vec::new(),
                )
            };

        let cells = (n_kinds as usize) * (n_kinds as usize);
        if sc_off.len() != cells
            || sc_len.len() != cells
            || pp_off.len() != cells
            || pp_len.len() != cells
        {
            return Err("parse tables: bad 2D table sizes".into());
        }
        if prod_arity.len() != n_productions as usize {
            return Err("parse tables: bad arity table size".into());
        }
        if prod_rhs_off.len() != n_productions as usize
            || prod_rhs_len.len() != n_productions as usize
        {
            return Err("parse tables: bad rhs table size".into());
        }
        if n_nonterminals > 0 {
            let predict_cells = (n_nonterminals as usize) * (n_kinds as usize);
            if ll1_predict.len() != predict_cells {
                return Err("parse tables: bad LL(1) predict table size".into());
            }
            if start_nonterminal >= n_nonterminals {
                return Err("parse tables: bad LL(1) start nonterminal".into());
            }
        }

        Ok(Self {
            n_kinds,
            n_productions,
            sc_superseq,
            sc_off,
            sc_len,
            sc_symbol_bits,
            pp_superseq,
            pp_off,
            pp_len,
            pp_prod_bits,
            prod_arity,
            n_nonterminals,
            start_nonterminal,
            ll1_predict,
            prod_rhs_off,
            prod_rhs_len,
            prod_rhs,
        })
    }
}

// ---------- Generator seed table ----------

/// Build a minimal, *correctly-shaped* set of tables that only handle bracket push/pop.
///
/// This is used by table-generation tooling as an initial data shape, not as a
/// runtime parser fallback.
/// - Stack symbols: 0=Paren, 1=Bracket
/// - Partial parse: empty everywhere (we’ll fill after we wire real grammar).
/// - Production arity: uses `prod_arity` passed in (possibly from a grammar scan).
pub fn build_mvp_precomputed_tables(n_kinds: u32, prod_arity: Vec<u32>) -> PrecomputedParseTables {
    let n_productions = prod_arity.len() as u32;
    let mut t = PrecomputedParseTables::new(n_kinds, n_productions);
    t.prod_arity = prod_arity;

    const SYM_PAREN: u32 = 0;
    const SYM_BRACK: u32 = 1;

    // For every prev kind, set sequences on open/close delimiters.
    for prev in 0..n_kinds {
        // Opens = push
        t.set_sc_for_pair(
            prev,
            TokenKind::GroupLParen as u32,
            &[encode_push(SYM_PAREN)],
        );
        t.set_sc_for_pair(
            prev,
            TokenKind::CallLParen as u32,
            &[encode_push(SYM_PAREN)],
        );
        t.set_sc_for_pair(
            prev,
            TokenKind::ParamLParen as u32,
            &[encode_push(SYM_PAREN)],
        );
        t.set_sc_for_pair(
            prev,
            TokenKind::ArrayLBracket as u32,
            &[encode_push(SYM_BRACK)],
        );
        t.set_sc_for_pair(
            prev,
            TokenKind::IndexLBracket as u32,
            &[encode_push(SYM_BRACK)],
        );
        t.set_sc_for_pair(
            prev,
            TokenKind::TypeArrayLBracket as u32,
            &[encode_push(SYM_BRACK)],
        );

        // Closes = typed pops by physical delimiter. Retagged closes are the normal path;
        // raw closes are compatibility recovery entries for malformed token streams.
        t.set_sc_for_pair(prev, TokenKind::RParen as u32, &[encode_pop(SYM_PAREN)]);
        t.set_sc_for_pair(
            prev,
            TokenKind::GroupRParen as u32,
            &[encode_pop(SYM_PAREN)],
        );
        t.set_sc_for_pair(prev, TokenKind::CallRParen as u32, &[encode_pop(SYM_PAREN)]);
        t.set_sc_for_pair(
            prev,
            TokenKind::ParamRParen as u32,
            &[encode_pop(SYM_PAREN)],
        );
        t.set_sc_for_pair(prev, TokenKind::RBracket as u32, &[encode_pop(SYM_BRACK)]);
        t.set_sc_for_pair(
            prev,
            TokenKind::ArrayRBracket as u32,
            &[encode_pop(SYM_BRACK)],
        );
        t.set_sc_for_pair(
            prev,
            TokenKind::IndexRBracket as u32,
            &[encode_pop(SYM_BRACK)],
        );
        t.set_sc_for_pair(
            prev,
            TokenKind::TypeArrayRBracket as u32,
            &[encode_pop(SYM_BRACK)],
        );

        // Empty partial parse everywhere (MVP).
        t.set_pp_for_pair(prev, TokenKind::GroupLParen as u32, &[]);
        t.set_pp_for_pair(prev, TokenKind::CallLParen as u32, &[]);
        t.set_pp_for_pair(prev, TokenKind::ParamLParen as u32, &[]);
        t.set_pp_for_pair(prev, TokenKind::ArrayLBracket as u32, &[]);
        t.set_pp_for_pair(prev, TokenKind::IndexLBracket as u32, &[]);
        t.set_pp_for_pair(prev, TokenKind::TypeArrayLBracket as u32, &[]);
        t.set_pp_for_pair(prev, TokenKind::RParen as u32, &[]);
        t.set_pp_for_pair(prev, TokenKind::GroupRParen as u32, &[]);
        t.set_pp_for_pair(prev, TokenKind::CallRParen as u32, &[]);
        t.set_pp_for_pair(prev, TokenKind::ParamRParen as u32, &[]);
        t.set_pp_for_pair(prev, TokenKind::RBracket as u32, &[]);
        t.set_pp_for_pair(prev, TokenKind::ArrayRBracket as u32, &[]);
        t.set_pp_for_pair(prev, TokenKind::IndexRBracket as u32, &[]);
        t.set_pp_for_pair(prev, TokenKind::TypeArrayRBracket as u32, &[]);
    }

    // Bit widths (symbol ids go up to 1 in MVP)
    t.finalize_bit_widths(1);
    t
}

impl PrecomputedParseTables {
    /// Produce a contiguous (n_kinds*n_kinds) array of ActionHeader as bytes,
    /// matching what `llp_pairs.slang` reads.
    pub fn to_action_header_grid_bytes(&self) -> Vec<u8> {
        use std::mem::size_of;
        let n = self.n_kinds as usize;
        let cell_count = n * n;
        let sz = size_of::<crate::parser::buffers::ActionHeader>();
        let mut out = vec![0u8; cell_count * sz];

        for prev in 0..self.n_kinds {
            for this in 0..self.n_kinds {
                let idx2d = (prev as usize) * n + (this as usize);

                // Stack-change seq for (prev,this)
                let sc_off = self.sc_off[idx2d] as usize;
                let sc_len = self.sc_len[idx2d] as usize;
                let sc = &self.sc_superseq[sc_off..sc_off + sc_len];

                // Count pushes/pops: push=odd, pop=even (encode_push/encode_pop)
                let mut push_len = 0u32;
                let mut pop_count = 0u32;
                for &code in sc {
                    if (code & 1) == 1 {
                        push_len += 1;
                    } else {
                        pop_count += 1;
                    }
                }

                // Partial-parse length is emit_len for this pair
                let emit_len = self.pp_len[idx2d];

                let hdr = crate::parser::buffers::ActionHeader {
                    push_len,
                    emit_len,
                    pop_tag: 0, // typed matching comes from the packed streams later
                    pop_count,
                };

                let off = idx2d * sz;
                out[off..off + 4].copy_from_slice(&hdr.push_len.to_le_bytes());
                out[off + 4..off + 8].copy_from_slice(&hdr.emit_len.to_le_bytes());
                out[off + 8..off + 12].copy_from_slice(&hdr.pop_tag.to_le_bytes());
                out[off + 12..off + 16].copy_from_slice(&hdr.pop_count.to_le_bytes());
            }
        }
        out
    }
}
