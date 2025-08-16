//! Host-side recount of EMIT/EOF using the same compact tables the GPU uses.
//! Useful to compare against GPU flags without touching gpu/driver.rs.

use anyhow::{Result, bail};

use crate::lexer::tables::{
    compact::load_compact_tables_from_bytes,
    dfa::N_STATES,
    tokens::TokenKind,
};

#[derive(Debug, Clone, Copy)]
pub struct HostRecount {
    pub emit: u64,
    pub eof: u64,
    pub all: u64,
    pub kept: u64,
    pub emit_kind_mismatch: u64,
}

pub fn recount_tables_host(input_bytes: &[u8]) -> Result<HostRecount> {
    const COMPACT_BIN: &[u8] = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tables/lexer_tables.bin"
    ));

    let (n_states_from_file, next_emit_words, token_map) =
        load_compact_tables_from_bytes(COMPACT_BIN).map_err(anyhow::Error::msg)?;

    if n_states_from_file != N_STATES {
        bail!(
            "compact table has n_states={} but code expects N_STATES={}",
            n_states_from_file,
            N_STATES
        );
    }

    let skip_kinds = [
        TokenKind::White as u32,
        TokenKind::LineComment as u32,
        TokenKind::BlockComment as u32,
        u32::MAX,
    ];

    let mut prev_state: u32 = 0; // start_state
    let n = input_bytes.len();

    let mut cnt_emit: u64 = 0;
    let mut cnt_eof: u64 = 0;
    let mut cnt_all: u64 = 0;
    let mut cnt_kept: u64 = 0;
    let mut emit_kind_mismatch: u64 = 0;

    let is_skip = |tk: u32| {
        tk == skip_kinds[0] || tk == skip_kinds[1] || tk == skip_kinds[2] || tk == skip_kinds[3]
    };

    for (i, &b) in input_bytes.iter().enumerate() {
        let idx = (b as usize) * (N_STATES as usize) + (prev_state as usize);
        let word = next_emit_words[idx >> 1];
        let lane16 = if (idx & 1) == 0 {
            word & 0xFFFF
        } else {
            (word >> 16) & 0xFFFF
        };

        let emit_here = (lane16 & 0x8000) != 0;
        let next_state = (lane16 & 0x7FFF) as u32;

        let at_eof = i + 1 == n;
        let tk_emit = token_map[prev_state as usize];
        let tk_eof = token_map[next_state as usize];

        if emit_here {
            cnt_emit += 1;
            if tk_emit == u32::MAX {
                // table inconsistency: EMIT flagged but no token kind at prev_state
                emit_kind_mismatch += 1;
            }
        }

        let eof_accept = at_eof && tk_eof != u32::MAX;
        if eof_accept {
            cnt_eof += 1;
        }

        cnt_all += (emit_here as u64) + (eof_accept as u64);

        let keep_emit = !is_skip(tk_emit) && tk_emit != u32::MAX;
        let keep_eof = !is_skip(tk_eof) && tk_eof != u32::MAX;
        cnt_kept += ((emit_here && keep_emit) as u64) + ((eof_accept && keep_eof) as u64);

        prev_state = next_state;
    }

    Ok(HostRecount {
        emit: cnt_emit,
        eof: cnt_eof,
        all: cnt_all,
        kept: cnt_kept,
        emit_kind_mismatch,
    })
}
