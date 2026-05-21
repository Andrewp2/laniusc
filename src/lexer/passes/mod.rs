use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{
        ComputePassBatch,
        DispatchDim,
        InputElements,
        PassData,
        compute_pass_batching_enabled,
        validation_scopes_enabled,
    },
    lexer::{Pass, buffers::GpuBuffers},
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
pub mod tokens_file_ids;

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
    pub tokens_file_ids: tokens_file_ids::TokensFileIdsPass,
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
            tokens_file_ids: tokens_file_ids::TokensFileIdsPass::new(&device)?,
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
    // Ensure flags_packed is zeroed so dfa_03 can write flags only at boundaries
    // and leave non-boundaries as 0 without per-byte stores.
    ctx.encoder.clear_buffer(&ctx.buffers.flags_packed, 0, None);

    let can_batch = ctx.maybe_timer.is_none()
        && ctx.maybe_dbg.is_none()
        && ctx.bg_cache.is_some()
        && compute_pass_batching_enabled()
        && !validation_scopes_enabled();
    if can_batch {
        {
            let bg_cache = ctx
                .bg_cache
                .as_deref_mut()
                .expect("batching requires bind-group cache");
            let mut batch = ComputePassBatch::begin(ctx.encoder, "lexer.dfa-local.batch");
            batch.record_pass_cached(ctx.device, ctx.buffers, bg_cache, &p.dfa_01, E1(n))?;
        }
        p.dfa_02.record_pass(&mut ctx, E1(nb_dfa))?;
        {
            let bg_cache = ctx
                .bg_cache
                .as_deref_mut()
                .expect("batching requires bind-group cache");
            bg_cache.remove(&p.dfa_03.data().shader_id);
            let mut batch = ComputePassBatch::begin(ctx.encoder, "lexer.dfa-pair-local.batch");
            batch.record_pass_cached(ctx.device, ctx.buffers, bg_cache, &p.dfa_03, E1(n))?;
            batch.record_pass_cached(ctx.device, ctx.buffers, bg_cache, &p.pair_01, E1(n))?;
        }
        p.pair_02.record_pass(&mut ctx, E1(nb_sum))?;
        {
            let bg_cache = ctx
                .bg_cache
                .as_deref_mut()
                .expect("batching requires bind-group cache");
            bg_cache.remove(&p.pair_03.data().shader_id);
            let mut batch = ComputePassBatch::begin(ctx.encoder, "lexer.emit.batch");
            batch.record_pass_cached(ctx.device, ctx.buffers, bg_cache, &p.pair_03, E1(n))?;
            batch.record_pass_cached(ctx.device, ctx.buffers, bg_cache, &p.compact_kept, E1(n))?;
            batch.record_pass_cached(ctx.device, ctx.buffers, bg_cache, &p.compact_all, E1(n))?;
            batch.record_pass_cached(ctx.device, ctx.buffers, bg_cache, &p.tokens_build, E1(n))?;
            batch.record_pass_cached(
                ctx.device,
                ctx.buffers,
                bg_cache,
                &p.tokens_file_ids,
                E1(n),
            )?;
        }
        return Ok(());
    }

    p.dfa_01.record_pass(&mut ctx, E1(n))?;
    p.dfa_02.record_pass(&mut ctx, E1(nb_dfa))?;
    if let Some(cache) = ctx.bg_cache.as_deref_mut() {
        cache.remove(&p.dfa_03.data().shader_id);
    }
    p.dfa_03.record_pass(&mut ctx, E1(n))?;
    p.pair_01.record_pass(&mut ctx, E1(n))?;
    p.pair_02.record_pass(&mut ctx, E1(nb_sum))?;
    if let Some(cache) = ctx.bg_cache.as_deref_mut() {
        cache.remove(&p.pair_03.data().shader_id);
    }
    p.pair_03.record_pass(&mut ctx, E1(n))?;
    // Run KEPT compaction before ALL to enable buffer reuse
    p.compact_kept.record_pass(&mut ctx, E1(n))?;
    p.compact_all.record_pass(&mut ctx, E1(n))?;
    p.tokens_build.record_pass(&mut ctx, E1(n))?;
    p.tokens_file_ids.record_pass(&mut ctx, E1(n))?;
    Ok(())
}
