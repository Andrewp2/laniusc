//! Types used by the GPU lexer.

use encase::ShaderType;

use crate::lexer::tables::tokens::TokenKind;

#[derive(Debug, Clone)]
/// Host-readable token record produced by GPU readback.
pub struct Token {
    /// Token kind after lexer-level filtering.
    pub kind: TokenKind,
    /// Start byte offset in the concatenated source input.
    pub start: usize,
    /// Token byte length.
    pub len: usize,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters shared by lexer GPU passes.
pub struct LexParams {
    /// Current source byte length.
    pub n: u32,
    /// Number of DFA states in the loaded table.
    pub m: u32,
    /// Initial DFA state for the stream.
    pub start_state: u32,
    /// First token kind excluded from final kept-token output.
    pub skip0: u32,
    /// Second token kind excluded from final kept-token output.
    pub skip1: u32,
    /// Third token kind excluded from final kept-token output.
    pub skip2: u32,
    /// Fourth token kind excluded from final kept-token output.
    pub skip3: u32,
}

#[derive(Clone, Copy, ShaderType, Default)]
/// GPU token record written by `tokens_build`.
pub struct GpuToken {
    /// Numeric `TokenKind` discriminant.
    pub kind: u32,
    /// Start byte offset in the concatenated source input.
    pub start: u32,
    /// Token byte length.
    pub len: u32,
}
