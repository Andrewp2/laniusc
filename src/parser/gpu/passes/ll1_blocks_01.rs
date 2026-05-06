use encase::ShaderType;

pub const LL1_BLOCK_STATUS_WORDS: usize = 10;
pub const LL1_BLOCK_STATUS_DISABLED: u32 = 0;
pub const LL1_BLOCK_STATUS_BOUNDARY: u32 = 1;
pub const LL1_BLOCK_STATUS_ACCEPTED: u32 = 2;
pub const LL1_BLOCK_STATUS_TRAILING: u32 = 3;
pub const LL1_BLOCK_STATUS_ERROR: u32 = 4;

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct LL1BlocksParams {
    pub n_tokens: u32,
    pub n_kinds: u32,
    pub n_nonterminals: u32,
    pub n_productions: u32,
    pub start_nonterminal: u32,
    pub first_input: u32,
    pub input_end: u32,
    pub n_blocks: u32,
    pub block_size: u32,
    pub stack_capacity: u32,
    pub emit_stride: u32,
    pub max_steps: u32,
    pub fill_production: u32,
    pub emit_scan_step: u32,
}
