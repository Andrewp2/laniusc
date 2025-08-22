use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, PassData},
    lexer::gpu::{Pass, buffers::GpuBuffers},
};

pub mod compact_boundaries_all;
pub mod compact_boundaries_kept;
pub mod dfa_01_scan_inblock;
pub mod dfa_02_scan_block_summaries;
pub mod dfa_03_apply_block_prefix;
pub mod pair_01_sum_inblock;
pub mod pair_02_scan_block_totals;
pub mod pair_03_apply_block_prefix;
pub mod tokens_build;

#[derive(ShaderType, Debug, Clone, Copy)]
pub(super) struct ScanParams {
    pub stride: u32,
    pub use_ping_as_src: u32,
}

pub struct LexerPasses {
    pub dfa_01: dfa_01_scan_inblock::Dfa01ScanInblockPass,
    pub dfa_02: dfa_02_scan_block_summaries::Dfa02ScanBlockSummariesPass,
    pub dfa_03: dfa_03_apply_block_prefix::Dfa03ApplyBlockPrefixPass,

    pub pair_01: pair_01_sum_inblock::Pair01SumInblockPass,
    pub pair_02: pair_02_scan_block_totals::Pair02ScanBlockTotalsPass,
    pub pair_03: pair_03_apply_block_prefix::Pair03ApplyBlockPrefixPass,

    pub compact_all: compact_boundaries_all::CompactBoundariesAllPass,
    pub compact_kept: compact_boundaries_kept::CompactBoundariesKeptPass,
    pub tokens_build: tokens_build::TokensBuildPass,
}

impl LexerPasses {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            dfa_01: dfa_01_scan_inblock::Dfa01ScanInblockPass::new(&device)?,
            dfa_02: dfa_02_scan_block_summaries::Dfa02ScanBlockSummariesPass::new(&device)?,
            dfa_03: dfa_03_apply_block_prefix::Dfa03ApplyBlockPrefixPass::new(&device)?,
            pair_01: pair_01_sum_inblock::Pair01SumInblockPass::new(&device)?,
            pair_02: pair_02_scan_block_totals::Pair02ScanBlockTotalsPass::new(&device)?,
            pair_03: pair_03_apply_block_prefix::Pair03ApplyBlockPrefixPass::new(&device)?,
            compact_all: compact_boundaries_all::CompactBoundariesAllPass::new(&device)?,
            compact_kept: compact_boundaries_kept::CompactBoundariesKeptPass::new(&device)?,
            tokens_build: tokens_build::TokensBuildPass::new(&device)?,
        })
    }
}

pub fn record_all_passes(
    n: u32,
    nb_dfa: u32,
    nb_sum: u32,
    mut ctx: crate::gpu::passes_core::PassContext<'_, GpuBuffers, super::debug::DebugOutput>,
    p: &LexerPasses,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1;
    p.dfa_01.record_pass(&mut ctx, E1(n))?;
    p.dfa_02.record_pass(&mut ctx, E1(nb_dfa))?;
    p.dfa_03.record_pass(&mut ctx, E1(n))?;
    p.pair_01.record_pass(&mut ctx, E1(n))?;
    p.pair_02.record_pass(&mut ctx, E1(nb_sum))?;
    p.pair_03.record_pass(&mut ctx, E1(n))?;
    // Run KEPT compaction before ALL to enable buffer reuse
    p.compact_kept.record_pass(&mut ctx, E1(n))?;
    p.compact_all.record_pass(&mut ctx, E1(n))?;
    p.tokens_build.record_pass(&mut ctx, E1(n))?;
    Ok(())
}
