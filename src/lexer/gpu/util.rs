//! Small helpers for readback and env flags.

use crate::lexer::{
    gpu::types::{GpuToken, Token},
    tables::tokens::TokenKind,
};

/// Read a little-endian u32 from the first 4 bytes.
pub fn u32_from_first_4(bytes: &[u8]) -> u32 {
    let mut le = [0u8; 4];
    le.copy_from_slice(&bytes[..4]);
    u32::from_le_bytes(le)
}

/// Treat any value other than "0"/"false" (case-insensitive) as true.
pub fn env_flag_true(var: &str, default: bool) -> bool {
    std::env::var(var)
        .map(|v| !(v == "0" || v.eq_ignore_ascii_case("false")))
        .unwrap_or(default)
}

/// Gate for token payload readback to the CPU (can be turned off in perf runs).
pub fn readback_enabled() -> bool {
    env_flag_true("LANIUS_READBACK", true) && env_flag_true("PERF_ONE_READBACK", true)
}

/// Convert a mapped `[GpuToken]` byte slice into a `Vec<Token>`.
pub fn read_tokens_from_mapped(bytes: &[u8], count: usize) -> Vec<Token> {
    use std::{mem::size_of, ptr::read_unaligned};

    let instant = std::time::Instant::now();
    let mut out = Vec::with_capacity(count);
    let mut p = bytes.as_ptr();
    let stride = size_of::<u32>() * 3;

    debug_assert!(
        bytes.len() >= count * stride,
        "read_tokens_from_mapped: mapped slice too small (have {}, need >= {})",
        bytes.len(),
        count * stride
    );

    for _ in 0..count {
        let kind_u32 = unsafe { read_unaligned(p as *const u32) };
        let start = unsafe { read_unaligned(p.add(4) as *const u32) } as usize;
        let len = unsafe { read_unaligned(p.add(8) as *const u32) } as usize;

        // SAFETY: TokenKind is repr(u32) in practice; same assumption as before.
        let kind = unsafe { std::mem::transmute::<u32, TokenKind>(kind_u32) };
        out.push(Token { kind, start, len });

        p = unsafe { p.add(stride) };
    }
    eprintln!(
        "[read_tokens_from_mapped] {} tokens in {:.3} ms",
        count,
        instant.elapsed().as_nanos() as f64 / 1.0e6
    );
    out
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
