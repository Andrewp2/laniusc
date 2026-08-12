use encase::ShaderType;

/// Enum variant rank scan passes.
pub mod rank;
/// Enum variant and payload record passes.
pub mod variant;

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters shared by enum and match lowering passes.
pub struct Params {
    pub n: u32,
    pub uses_status_count: u32,
    /// Bit 0: enum records are present. Bit 1: match records are present.
    pub family_flags: u32,
    pub retain_debug_rows: u32,
}
