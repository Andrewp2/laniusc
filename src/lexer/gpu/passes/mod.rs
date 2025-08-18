use encase::ShaderType;

use crate::gpu::passes_core::{DispatchDim, InputElements, PassData};

pub mod boundary_finalize_and_seed;
pub mod compact_boundaries_all;
pub mod compact_boundaries_kept;
pub mod dfa_01_scan_inblock;
pub mod dfa_02_scan_block_summaries;
pub mod dfa_03_apply_block_prefix;
pub mod pair_01_sum_inblock;
pub mod pair_02_scan_block_totals;
pub mod pair_03_apply_block_prefix;
pub mod retag_calls_and_arrays;
pub mod tokens_build;

#[derive(ShaderType, Debug, Clone, Copy)]
pub(super) struct ScanParams {
    pub stride: u32,
    pub use_ping_as_src: u32,
}
