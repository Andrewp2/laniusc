//! Types used by the GPU lexer.

use encase::ShaderType;

use crate::lexer::tables::tokens::TokenKind;

#[derive(Debug, Clone)]
pub struct Token {
    pub kind: TokenKind,
    pub start: usize,
    pub len: usize,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct LexParams {
    pub n: u32,
    pub m: u32,
    pub start_state: u32,
    pub skip0: u32,
    pub skip1: u32,
    pub skip2: u32,
    pub skip3: u32,
}

#[derive(Clone, Copy, ShaderType, Default)]
pub struct GpuToken {
    pub kind: u32,
    pub start: u32,
    pub len: u32,
}
