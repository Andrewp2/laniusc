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

    let total = 256 * N_STATES;
    let mut next_emit_u16 = Vec::<u16>::with_capacity(total);
    for b in 0u32..=255 {
        for s in 0..N_STATES {
            let nx = dfa.next[s][b as usize];
            let next = nx.state & 0x7FFF;
            let emit = if nx.emit { 1u16 } else { 0u16 };
            next_emit_u16.push((emit << 15) | next);
        }
    }

    let mut token_u16 = Vec::<u16>::with_capacity(N_STATES);
    for &tk in &dfa.token_map {
        token_u16.push(if tk == INVALID_TOKEN {
            0xFFFF
        } else {
            tk as u16
        });
    }

    let out_path = Path::new("tables/lexer_tables.bin");
    if let Some(dir) = out_path.parent() {
        fs::create_dir_all(dir)?;
    }

    let f = fs::File::create(out_path)?;
    let mut w = BufWriter::new(f);

    w.write_all(MAGIC)?;
    w.write_all(&(N_STATES as u32).to_le_bytes())?;
    w.write_all(&0u32.to_le_bytes())?;
    for v in &next_emit_u16 {
        w.write_all(&v.to_le_bytes())?;
    }
    for v in &token_u16 {
        w.write_all(&v.to_le_bytes())?;
    }
    w.flush()?;

    let bytes = 8 + 4 + 4 + next_emit_u16.len() * 2 + token_u16.len() * 2;
    println!(
        "[gen_tables] wrote {} bytes (~{:.1} KiB) → {}",
        bytes,
        bytes as f64 / 1024.0,
        out_path.display()
    );
    Ok(())
}
