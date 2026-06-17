//! Small helpers for readback and env flags.

use crate::{
    gpu,
    lexer::{tables::tokens::TokenKind, types::Token},
};

/// Read a little-endian u32 from the first 4 bytes.
pub fn u32_from_first_4(bytes: &[u8]) -> u32 {
    let mut le = [0u8; 4];
    le.copy_from_slice(&bytes[..4]);
    u32::from_le_bytes(le)
}

/// Treat any value other than "0"/"false" (case-insensitive) as true.
pub fn env_flag_true(var: &str, default: bool) -> bool {
    gpu::env::env_bool_truthy(var, default)
}

/// Gate for host readback of token payloads (can be turned off in perf runs).
pub fn readback_enabled() -> bool {
    env_flag_true("LANIUS_READBACK", true) && env_flag_true("PERF_ONE_READBACK", true)
}

/// Convert a mapped `[GpuToken]` byte slice into a `Vec<Token>`.
pub fn read_tokens_from_mapped(bytes: &[u8], count: usize) -> Result<Vec<Token>, String> {
    use std::mem::size_of;

    let stride = size_of::<u32>() * 3;
    let needed = count
        .checked_mul(stride)
        .ok_or_else(|| "read_tokens_from_mapped: byte count overflow".to_string())?;
    if bytes.len() < needed {
        return Err(format!(
            "read_tokens_from_mapped: mapped slice too small (have {}, need >= {})",
            bytes.len(),
            needed
        ));
    }

    let mut out = Vec::with_capacity(count);
    for (i, raw) in bytes[..needed].chunks_exact(stride).enumerate() {
        let kind_u32 = u32::from_le_bytes(raw[0..4].try_into().expect("kind word"));
        let start = u32::from_le_bytes(raw[4..8].try_into().expect("start word")) as usize;
        let len = u32::from_le_bytes(raw[8..12].try_into().expect("len word")) as usize;

        let kind = TokenKind::from_u32(kind_u32).ok_or_else(|| {
            format!("read_tokens_from_mapped: invalid token kind {kind_u32} at token {i}")
        })?;
        out.push(Token { kind, start, len });
    }
    Ok(out)
}

pub fn compute_rounds(val: u32) -> u32 {
    let mut r = 0u32;
    let mut s = 1u32;
    while s < val {
        r += 1;
        s <<= 1;
    }
    r
}

#[cfg(test)]
mod tests {
    use super::*;

    fn token_bytes(kind: u32, start: u32, len: u32) -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&kind.to_le_bytes());
        bytes.extend_from_slice(&start.to_le_bytes());
        bytes.extend_from_slice(&len.to_le_bytes());
        bytes
    }

    #[test]
    fn read_tokens_from_mapped_decodes_valid_kind() {
        let bytes = token_bytes(TokenKind::Ident as u32, 4, 3);

        let tokens = read_tokens_from_mapped(&bytes, 1).expect("valid token readback");

        assert_eq!(tokens.len(), 1);
        assert_eq!(tokens[0].kind, TokenKind::Ident);
        assert_eq!(tokens[0].start, 4);
        assert_eq!(tokens[0].len, 3);
    }

    #[test]
    fn read_tokens_from_mapped_rejects_invalid_kind() {
        let bytes = token_bytes(0, 4, 3);

        let err = read_tokens_from_mapped(&bytes, 1).expect_err("invalid token kind");

        assert!(
            err.contains("invalid token kind 0"),
            "unexpected error: {err}"
        );
    }
}
