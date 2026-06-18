use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{
        ComputePassBatch,
        InputElements,
        compute_pass_batching_enabled,
        validation_scopes_enabled,
    },
    lexer::{Pass, buffers::GpuBuffers},
};

/// Boundary compaction passes.
pub mod compact;
/// DFA scanning passes.
pub mod dfa;
/// Token-boundary prefix-sum passes.
pub mod pair;
/// Source-pack source-file boundary pass.
pub mod source_file_boundaries;
/// Final token-record construction pass.
pub mod tokens_build;

#[derive(ShaderType, Debug, Clone, Copy)]
/// Uniform parameters for one prefix-scan round.
pub(super) struct ScanParams {
    /// Prefix-scan stride for this round.
    pub stride: u32,
    /// Whether the ping buffer is the source for this round.
    pub use_ping_as_src: u32,
}

/// All GPU passes that make up one lexer pipeline.
pub struct LexerPasses {
    /// Scans DFA state transitions inside each byte block.
    pub dfa_01: dfa::scan_inblock::Dfa01ScanInblockPass,
    /// Prefix-scans DFA block summaries.
    pub dfa_02: dfa::scan_block_summaries::Dfa02ScanBlockSummariesPass,
    /// Applies DFA block prefixes and emits boundary flags.
    pub dfa_03: dfa::apply_block_prefix::Dfa03ApplyBlockPrefixPass,
    /// Marks source-pack file start/end byte offsets.
    pub source_file_boundaries: source_file_boundaries::SourceFileBoundariesPass,

    /// Counts all/kept token boundaries inside each block.
    pub pair_01: pair::sum_inblock::Pair01SumInblockPass,
    /// Prefix-scans per-block token-boundary totals.
    pub pair_02: pair::scan_block_totals::Pair02ScanBlockTotalsPass,
    /// Applies pair prefixes to produce compacted token ranks.
    pub pair_03: pair::apply_block_prefix::Pair03ApplyBlockPrefixPass,

    /// Compacts all token boundaries, including skipped tokens.
    pub compact_all: compact::boundaries::all::CompactBoundariesAllPass,
    /// Compacts kept token boundaries.
    pub compact_kept: compact::boundaries::kept::CompactBoundariesKeptPass,
    /// Builds final resident token records.
    pub tokens_build: tokens_build::TokensBuildPass,
}

impl LexerPasses {
    /// Creates every lexer shader pass for a device.
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            dfa_01: dfa::scan_inblock::Dfa01ScanInblockPass::new(&device)?,
            dfa_02: dfa::scan_block_summaries::Dfa02ScanBlockSummariesPass::new(&device)?,
            dfa_03: dfa::apply_block_prefix::Dfa03ApplyBlockPrefixPass::new(&device)?,
            source_file_boundaries: source_file_boundaries::SourceFileBoundariesPass::new(&device)?,
            pair_01: pair::sum_inblock::Pair01SumInblockPass::new(&device)?,
            pair_02: pair::scan_block_totals::Pair02ScanBlockTotalsPass::new(&device)?,
            pair_03: pair::apply_block_prefix::Pair03ApplyBlockPrefixPass::new(&device)?,
            compact_all: compact::boundaries::all::CompactBoundariesAllPass::new(&device)?,
            compact_kept: compact::boundaries::kept::CompactBoundariesKeptPass::new(&device)?,
            tokens_build: tokens_build::TokensBuildPass::new(&device)?,
        })
    }
}

/// Records the full lexer pass sequence for the current resident buffers.
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
    ctx.encoder
        .clear_buffer(&ctx.buffers.source_file_start_flags, 0, None);
    ctx.encoder
        .clear_buffer(&ctx.buffers.source_file_end_flags, 0, None);
    let source_file_capacity = ctx.buffers.source_file_start.count as u32;

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
            batch.record_pass_cached(
                ctx.device,
                ctx.buffers,
                bg_cache,
                &p.source_file_boundaries,
                E1(source_file_capacity),
            )?;
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
        }
        return Ok(());
    }

    p.source_file_boundaries
        .record_pass(&mut ctx, E1(source_file_capacity))?;
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
    Ok(())
}
