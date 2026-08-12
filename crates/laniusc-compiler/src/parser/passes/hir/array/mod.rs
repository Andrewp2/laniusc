use encase::ShaderType;

/// Array-element list passes.
pub mod element;

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters shared by HIR array lowering passes.
pub struct Params {
    pub n: u32,
    pub uses_status_count: u32,
    pub retain_debug_rows: u32,
}
