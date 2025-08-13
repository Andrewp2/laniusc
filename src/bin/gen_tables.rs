// src/bin/gen_tables.rs
// Generates a tiny DFA table file with only what the GPU runtime actually uses:
// - next_emit: for each byte and state, pack (emit<<15 | next_state_low15)
// - token_map: token kind per DFA state (0xFFFF = invalid)
// Format:
//   magic: 8 bytes = "LXDFA001"
//   u32:   n_states
//   u32:   reserved (0)
//   u16[256 * n_states]: next_emit
//   u16[n_states]:       token_map (INVALID=0xFFFF)

use std::{
    fs,
    io::{BufWriter, Write},
    path::Path,
};

use laniusc::lexer::tables::{
    dfa::{N_STATES, StreamingDfa},
    tokens::INVALID_TOKEN,
};

const MAGIC: &[u8; 8] = b"LXDFA001";

fn main() -> std::io::Result<()> {
    println!("[gen_tables] building compact DFA tables (no merge)...");
    let dfa = StreamingDfa::new();
    let n_states = N_STATES as u32;

    // Build next_emit (u16) : 256 * N_STATES
    let total = 256 * N_STATES;
    let mut next_emit_u16: Vec<u16> = Vec::with_capacity(total);
    for b in 0u32..=255 {
        for s in 0..N_STATES {
            let nx = dfa.next[s][b as usize];
            let next = (nx.state & 0x7FFF) as u16;
            let emit = if nx.emit { 1u16 } else { 0u16 };
            next_emit_u16.push((emit << 15) | next);
        }
    }

    // token_map (u16) : N_STATES (INVALID_TOKEN -> 0xFFFF)
    let mut token_u16: Vec<u16> = Vec::with_capacity(N_STATES);
    for &tk in &dfa.token_map {
        if tk == INVALID_TOKEN {
            token_u16.push(0xFFFF);
        } else {
            token_u16.push(u16::try_from(tk).unwrap_or(0xFFFF));
        }
    }

    // Ensure output dir
    let out_path = Path::new("tables/lexer_tables.bin");
    if let Some(dir) = out_path.parent() {
        fs::create_dir_all(dir)?;
    }

    let f = fs::File::create(out_path)?;
    let mut w = BufWriter::new(f);

    // header
    w.write_all(MAGIC)?;
    w.write_all(&n_states.to_le_bytes())?;
    w.write_all(&0u32.to_le_bytes())?;

    // body
    for v in &next_emit_u16 {
        w.write_all(&v.to_le_bytes())?;
    }
    for v in &token_u16 {
        w.write_all(&v.to_le_bytes())?;
    }
    w.flush()?;

    let bytes = 8 + 4 + 4 + (next_emit_u16.len() * 2) + (token_u16.len() * 2);
    println!(
        "[gen_tables] wrote {} bytes (~{:.1} KiB) to {}",
        bytes,
        bytes as f64 / 1024.0,
        out_path.display()
    );
    println!("[gen_tables] done. You can commit this file safely.");
    Ok(())
}
