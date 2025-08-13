// src/lexer/tables/compact.rs
// Loader for the compact DFA table produced by the new gen_tables:
//   magic: 8  bytes  = "LXDFA001"
//   u32:   n_states
//   u32:   reserved (0)
//   u16:   next_emit[256 * n_states]   // (emit<<15 | next_low15)
//   u16:   token_map[n_states]         // INVALID=0xFFFF, else token kind as u16

use super::tokens::INVALID_TOKEN;

const MAGIC: &[u8; 8] = b"LXDFA001";

#[inline]
fn take_u32(buf: &mut &[u8]) -> Result<u32, String> {
    if buf.len() < 4 {
        return Err("truncated u32".into());
    }
    let mut le = [0u8; 4];
    le.copy_from_slice(&buf[..4]);
    *buf = &buf[4..];
    Ok(u32::from_le_bytes(le))
}

#[inline]
fn take_u16(buf: &mut &[u8]) -> Result<u16, String> {
    if buf.len() < 2 {
        return Err("truncated u16".into());
    }
    let mut le = [0u8; 2];
    le.copy_from_slice(&buf[..2]);
    *buf = &buf[2..];
    Ok(u16::from_le_bytes(le))
}

/// Returns: (n_states, next_emit_packed_u32, token_map_u32)
pub fn load_compact_tables_from_bytes(
    mut data: &[u8],
) -> Result<(usize, Vec<u32>, Vec<u32>), String> {
    if data.len() < 8 + 4 + 4 {
        return Err("compact bin too short".into());
    }

    let mut magic = [0u8; 8];
    magic.copy_from_slice(&data[..8]);
    if &magic != MAGIC {
        return Err("bad magic in compact tables .bin".into());
    }
    data = &data[8..];

    let n_states = take_u32(&mut data)? as usize;
    let _reserved = take_u32(&mut data)?;

    // Read next_emit as u16, then pack 2x u16 per u32 (exactly what GPU buffer expects).
    let ne_len = 256usize
        .checked_mul(n_states)
        .ok_or_else(|| "n_states overflow".to_string())?;
    let mut next_emit_u16 = Vec::with_capacity(ne_len);
    for _ in 0..ne_len {
        next_emit_u16.push(take_u16(&mut data)?);
    }

    let mut next_emit_words: Vec<u32> = vec![0; (ne_len + 1) / 2];
    for (i, &v) in next_emit_u16.iter().enumerate() {
        let w = i >> 1;
        if (i & 1) == 0 {
            next_emit_words[w] |= v as u32;
        } else {
            next_emit_words[w] |= (v as u32) << 16;
        }
    }

    // token_map
    let mut token_map_u32 = Vec::with_capacity(n_states);
    for _ in 0..n_states {
        let v = take_u16(&mut data)?;
        token_map_u32.push(if v == 0xFFFF { INVALID_TOKEN } else { v as u32 });
    }

    Ok((n_states, next_emit_words, token_map_u32))
}
