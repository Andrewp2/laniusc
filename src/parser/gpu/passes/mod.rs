// Parser passes use the shared Pass trait from gpu::passes_core.
use anyhow::Result;

use crate::{
    gpu::passes_core::{InputElements, Pass, PassContext},
    parser::gpu::{buffers::ParserBuffers, debug::DebugOutput},
};

pub mod brackets_01;
pub mod brackets_02;
pub mod brackets_03;
pub mod brackets_04;
pub mod brackets_05;
pub mod brackets_06;
pub mod brackets_pse_04;

pub mod hir_item_fields;
pub mod hir_nodes;
pub mod hir_spans;
pub mod ll1_blocks_01;
pub mod ll1_blocks_02;
pub mod ll1_blocks_03;
pub mod ll1_blocks_04;
pub mod ll1_blocks_04_scan;
pub mod llp_pairs;
pub mod pack_offsets;
pub mod pack_offsets_status;
pub mod pack_varlen;
pub mod tree_parent;
pub mod tree_prefix_01;
pub mod tree_prefix_02;
pub mod tree_prefix_03;
pub mod tree_prefix_04;
pub mod tree_spans;

/// Bundle of all parser passes.
pub struct ParserPasses {
    pub ll1_blocks_02: ll1_blocks_02::LL1BlocksStitchPass,
    pub ll1_blocks_03: ll1_blocks_03::LL1BlocksSeededPass,
    pub ll1_blocks_04_scan: ll1_blocks_04_scan::LL1BlocksEmitPrefixScanPass,
    pub ll1_blocks_04: ll1_blocks_04::LL1BlocksFlattenEmitPass,
    pub llp_pairs: llp_pairs::LLPPairsPass,
    pub pack_offsets: pack_offsets::PackOffsetsScanPass,
    pub pack_offsets_status: pack_offsets_status::PackOffsetsStatusPass,
    pub pack_varlen: pack_varlen::PackVarlenPass,

    // Bracket matching passes
    pub b01: brackets_01::BracketsScanInblockPass,
    pub b02: brackets_02::BracketsScanBlockPrefixPass,
    pub b03: brackets_03::BracketsApplyPrefixPass,
    pub b04: brackets_04::BracketsHistogramLayersPass,
    pub b05: brackets_05::BracketsScanHistogramsPass,
    pub b06: brackets_06::BracketsScatterByLayerPass,
    pub pse04: brackets_pse_04::BracketsPsePairPass, // Replaces b07

    // Tree building pass
    pub tree_prefix_01: tree_prefix_01::TreePrefixLocalPass,
    pub tree_prefix_02: tree_prefix_02::TreePrefixScanBlocksPass,
    pub tree_prefix_03: tree_prefix_03::TreePrefixApplyPass,
    pub tree_prefix_04: tree_prefix_04::TreePrefixMaxBuildPass,
    pub tree_parent: tree_parent::TreeParentPass,
    pub tree_spans: tree_spans::TreeSpansPass,

    // HIR-facing classification
    pub hir_nodes: hir_nodes::HirNodesPass,
    pub hir_spans: hir_spans::HirSpansPass,
    pub hir_item_fields: hir_item_fields::HirItemFieldsPass,
}

impl ParserPasses {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            ll1_blocks_02: ll1_blocks_02::LL1BlocksStitchPass::new(device)?,
            ll1_blocks_03: ll1_blocks_03::LL1BlocksSeededPass::new(device)?,
            ll1_blocks_04_scan: ll1_blocks_04_scan::LL1BlocksEmitPrefixScanPass::new(device)?,
            ll1_blocks_04: ll1_blocks_04::LL1BlocksFlattenEmitPass::new(device)?,
            llp_pairs: llp_pairs::LLPPairsPass::new(device)?,
            pack_offsets: pack_offsets::PackOffsetsScanPass::new(device)?,
            pack_offsets_status: pack_offsets_status::PackOffsetsStatusPass::new(device)?,
            pack_varlen: pack_varlen::PackVarlenPass::new(device)?,

            b01: brackets_01::BracketsScanInblockPass::new(device)?,
            b02: brackets_02::BracketsScanBlockPrefixPass::new(device)?,
            b03: brackets_03::BracketsApplyPrefixPass::new(device)?,
            b04: brackets_04::BracketsHistogramLayersPass::new(device)?,
            b05: brackets_05::BracketsScanHistogramsPass::new(device)?,
            b06: brackets_06::BracketsScatterByLayerPass::new(device)?,
            pse04: brackets_pse_04::BracketsPsePairPass::new(device)?,

            tree_parent: tree_parent::TreeParentPass::new(device)?,
            tree_prefix_01: tree_prefix_01::TreePrefixLocalPass::new(device)?,
            tree_prefix_02: tree_prefix_02::TreePrefixScanBlocksPass::new(device)?,
            tree_prefix_03: tree_prefix_03::TreePrefixApplyPass::new(device)?,
            tree_prefix_04: tree_prefix_04::TreePrefixMaxBuildPass::new(device)?,
            tree_spans: tree_spans::TreeSpansPass::new(device)?,
            hir_nodes: hir_nodes::HirNodesPass::new(device)?,
            hir_spans: hir_spans::HirSpansPass::new(device)?,
            hir_item_fields: hir_item_fields::HirItemFieldsPass::new(device)?,
        })
    }
}

/// Record the whole pipeline in order.
pub fn record_all_passes(
    mut ctx: PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1D;

    // 0) Stitched LL(1) seeds, seeded block production summaries, flattened
    // canonical LL(1) stream, then pair→header + pack.
    let n_ll1_blocks = ctx.buffers.ll1_n_blocks;
    p.ll1_blocks_02
        .record_pass(&mut ctx, E1D(n_ll1_blocks.saturating_mul(256)))?;
    p.ll1_blocks_03
        .record_pass(&mut ctx, E1D(n_ll1_blocks.saturating_mul(256)))?;
    p.ll1_blocks_04_scan
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.ll1_blocks_04
        .record_pass(&mut ctx, E1D(n_ll1_blocks.max(2).saturating_mul(256)))?;

    let n_pairs = ctx.buffers.n_tokens.saturating_sub(1);
    p.llp_pairs.record_pass(&mut ctx, E1D(n_pairs))?;
    p.pack_offsets
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.pack_offsets_status
        .record_pass(ctx.device, ctx.encoder, ctx.buffers)?;
    p.pack_varlen
        .record_pass(&mut ctx, E1D(n_pairs.saturating_mul(256)))?;

    // 1) Brackets (parallel)
    let n_sc = ctx.buffers.total_sc;
    let n_layers = ctx.buffers.b_n_layers;

    // Bracket matching - depth computation (same as before)
    p.b01.record_pass(&mut ctx, E1D(n_sc))?;
    p.b02.record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.b03.record_pass(&mut ctx, E1D(n_sc))?;

    // Bracket matching - PSE-style pairing
    p.b04.record_pass(&mut ctx, E1D(n_sc))?; // Histogram layers
    p.b05.record_scan(ctx.device, ctx.encoder, ctx.buffers)?; // Prefix sum over histograms

    // Scatter pushes and pops by layer
    {
        let bytes = (n_layers.max(1) * 4) as u64;
        ctx.encoder.copy_buffer_to_buffer(
            &ctx.buffers.b_off_push,
            0,
            &ctx.buffers.b_cur_push,
            0,
            bytes,
        );
        ctx.encoder.copy_buffer_to_buffer(
            &ctx.buffers.b_off_pop,
            0,
            &ctx.buffers.b_cur_pop,
            0,
            bytes,
        );
    }

    p.b06.record_pass(&mut ctx, E1D(n_sc))?; // Scatter by layer
    p.pse04.record_pass(&mut ctx, E1D(n_sc))?; // PSE-style pairing

    // Tree parent recovery: one independent thread per emitted production.
    let n_tree = ctx.buffers.tree_capacity;
    let n_tree_node_threads = ctx.buffers.tree_n_node_blocks.saturating_mul(256);
    let n_tree_prefix_positions = ctx.buffers.tree_capacity.saturating_add(1);
    p.tree_prefix_01
        .record_pass(&mut ctx, E1D(n_tree_node_threads))?;
    p.tree_prefix_02
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.tree_prefix_03
        .record_pass(&mut ctx, E1D(n_tree_prefix_positions))?;
    p.tree_prefix_04
        .record_build(ctx.device, ctx.encoder, ctx.buffers)?;
    p.tree_parent.record_pass(&mut ctx, E1D(n_tree))?;
    p.tree_spans.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_nodes.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_spans.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_item_fields.record_pass(&mut ctx, E1D(n_tree))?;

    Ok(())
}
