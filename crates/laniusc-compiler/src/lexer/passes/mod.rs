use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{
        ComputePassBatch,
        InputElements,
        validation_scopes_enabled,
    },
    lexer::{Pass, buffers::GpuBuffers},
};

/// Final token-record construction pass.
pub mod build_tokens;
/// Compaction pass for all token boundaries.
pub mod compact_all_token_boundaries;
/// Compaction pass for kept token boundaries.
pub mod compact_kept_token_boundaries;
/// Counts token boundaries inside blocks.
pub mod count_token_boundaries_in_blocks;
/// Source-pack source-file boundary pass.
pub mod mark_source_file_boundaries;
/// Applies DFA block prefixes to per-byte state.
pub mod mark_token_boundaries;
/// Applies token-boundary block prefixes.
pub mod rank_token_boundaries;
/// Prefix-scans DFA block summaries.
pub mod scan_dfa_block_summaries;
/// Prefix-scans token-boundary block totals.
pub mod scan_token_boundary_counts;
/// Scans DFA state transitions inside blocks.
pub mod summarize_dfa_blocks;
/// Scan steps shared by the token-boundary count and rank passes.
pub mod token_boundary_scan_steps;

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
    pub dfa_01: summarize_dfa_blocks::Dfa01ScanInblockPass,
    /// Prefix-scans DFA block summaries.
    pub dfa_02: scan_dfa_block_summaries::Dfa02ScanBlockSummariesPass,
    /// Applies DFA block prefixes and emits boundary flags.
    pub dfa_03: mark_token_boundaries::Dfa03ApplyBlockPrefixPass,
    /// Marks source-pack file start/end byte offsets.
    pub source_file_boundaries: mark_source_file_boundaries::SourceFileBoundariesPass,

    /// Counts all/kept token boundaries inside each block.
    pub pair_01: count_token_boundaries_in_blocks::Pair01SumInblockPass,
    /// Prefix-scans per-block token-boundary totals.
    pub pair_02: scan_token_boundary_counts::Pair02ScanBlockTotalsPass,
    /// Applies pair prefixes to produce compacted token ranks.
    pub pair_03: rank_token_boundaries::Pair03ApplyBlockPrefixPass,

    /// Compacts all token boundaries, including skipped tokens.
    pub compact_all: compact_all_token_boundaries::CompactBoundariesAllPass,
    /// Compacts kept token boundaries.
    pub compact_kept: compact_kept_token_boundaries::CompactBoundariesKeptPass,
    /// Builds final resident token records.
    pub tokens_build: build_tokens::TokensBuildPass,
    /// The desugaring after the token build, with its own buffers and floors.
    pub(crate) desugaring: std::sync::Arc<crate::compiler::desugar::Desugaring>,
}

impl LexerPasses {
    /// Creates every lexer shader pass for a device.
    pub fn new(device: &wgpu::Device, queue: &wgpu::Queue) -> Result<Self> {
        Ok(Self {
            dfa_01: summarize_dfa_blocks::Dfa01ScanInblockPass::new(&device)?,
            dfa_02: scan_dfa_block_summaries::Dfa02ScanBlockSummariesPass::new(&device)?,
            dfa_03: mark_token_boundaries::Dfa03ApplyBlockPrefixPass::new(&device)?,
            source_file_boundaries: mark_source_file_boundaries::SourceFileBoundariesPass::new(&device)?,
            pair_01: count_token_boundaries_in_blocks::Pair01SumInblockPass::new(&device)?,
            pair_02: scan_token_boundary_counts::Pair02ScanBlockTotalsPass::new(&device)?,
            pair_03: rank_token_boundaries::Pair03ApplyBlockPrefixPass::new(&device)?,
            compact_all: compact_all_token_boundaries::CompactBoundariesAllPass::new(&device)?,
            compact_kept: compact_kept_token_boundaries::CompactBoundariesKeptPass::new(&device)?,
            tokens_build: build_tokens::TokensBuildPass::new(&device)?,
            desugaring: crate::compiler::desugar::Desugaring::new(device, queue),
        })
    }
}

/// Records the full lexer pass sequence for the current resident buffers:
/// the lexer's passes, then the desugaring.
pub fn record_all_passes(
    n: u32,
    nb_dfa: u32,
    nb_sum: u32,
    mut ctx: crate::gpu::passes_core::PassContext<'_, GpuBuffers, super::debug::DebugOutput>,
    p: &LexerPasses,
) -> Result<(), anyhow::Error> {
    record_lexer_passes(n, nb_dfa, nb_sum, &mut ctx, p)?;
    record_desugar_passes(&mut ctx, p)
}

/// Records the desugaring after the token build of `record_lexer_passes`.
pub fn record_desugar_passes(
    ctx: &mut crate::gpu::passes_core::PassContext<'_, GpuBuffers, super::debug::DebugOutput>,
    p: &LexerPasses,
) -> Result<(), anyhow::Error> {
    let _operation_capture = ctx
        .maybe_timer
        .as_deref()
        .map(crate::gpu::timer::GpuTimer::capture_operations);
    crate::compiler::desugar::record(ctx, &p.desugaring)
}

/// Records the lexer's passes up to the token build.
pub fn record_lexer_passes(
    n: u32,
    nb_dfa: u32,
    nb_sum: u32,
    ctx: &mut crate::gpu::passes_core::PassContext<'_, GpuBuffers, super::debug::DebugOutput>,
    p: &LexerPasses,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1;
    let _operation_capture = ctx
        .maybe_timer
        .as_deref()
        .map(crate::gpu::timer::GpuTimer::capture_operations);
    // Reset values that are either accumulated atomically or only written at
    // token boundaries. These are logical graph resources even when workspace
    // coloring places them inside larger shared allocations.
    ctx.buffers.record_job_initialize(ctx.encoder);
    let source_file_capacity = ctx.buffers.source_file_start.count as u32;

    let can_batch = ctx.maybe_dbg.is_none()
        && ctx.bg_cache.is_some()
        && !crate::gpu::timer::operation_capture_requires_split_passes()
        && !validation_scopes_enabled();
    if can_batch {
        let lexer_span = crate::gpu::trace::HostSpan::new("host.lexer", "lex.record.lexer_passes");
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
        p.dfa_02.record_pass(ctx, E1(nb_dfa))?;
        {
            let bg_cache = ctx
                .bg_cache
                .as_deref_mut()
                .expect("batching requires bind-group cache");
            let mut batch = ComputePassBatch::begin(ctx.encoder, "lexer.dfa-pair-local.batch");
            batch.record_pass_cached(ctx.device, ctx.buffers, bg_cache, &p.dfa_03, E1(n))?;
            batch.record_pass_cached(ctx.device, ctx.buffers, bg_cache, &p.pair_01, E1(n))?;
        }
        p.pair_02.record_pass(ctx, E1(nb_sum))?;
        {
            let bg_cache = ctx
                .bg_cache
                .as_deref_mut()
                .expect("batching requires bind-group cache");
            let mut batch = ComputePassBatch::begin(ctx.encoder, "lexer.emit.batch");
            batch.record_pass_cached(ctx.device, ctx.buffers, bg_cache, &p.pair_03, E1(n))?;
            batch.record_pass_cached(ctx.device, ctx.buffers, bg_cache, &p.compact_kept, E1(n))?;
            batch.record_pass_cached(ctx.device, ctx.buffers, bg_cache, &p.compact_all, E1(n))?;
            batch.record_pass_cached(ctx.device, ctx.buffers, bg_cache, &p.tokens_build, E1(n))?;
        }
        drop(lexer_span);
        return Ok(());
    }

    p.source_file_boundaries
        .record_pass(ctx, E1(source_file_capacity))?;
    p.dfa_01.record_pass(ctx, E1(n))?;
    p.dfa_02.record_pass(ctx, E1(nb_dfa))?;
    p.dfa_03.record_pass(ctx, E1(n))?;
    p.pair_01.record_pass(ctx, E1(n))?;
    p.pair_02.record_pass(ctx, E1(nb_sum))?;
    p.pair_03.record_pass(ctx, E1(n))?;
    // Run KEPT compaction before ALL to enable buffer reuse
    p.compact_kept.record_pass(ctx, E1(n))?;
    p.compact_all.record_pass(ctx, E1(n))?;
    p.tokens_build.record_pass(ctx, E1(n))?;
    Ok(())
}
