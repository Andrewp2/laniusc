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

pub mod llp_pairs;
pub mod pack_varlen;

pub mod tree_blocked_01;
pub mod tree_blocked_02;
pub mod tree_blocked_03;

/// Bundle of all parser passes.
pub struct ParserPasses {
    pub llp_pairs: llp_pairs::LLPPairsPass,
    pub pack_varlen: pack_varlen::PackVarlenPass,

    // Bracket matching passes
    pub b01: brackets_01::BracketsScanInblockPass,
    pub b02: brackets_02::BracketsScanBlockPrefixPass,
    pub b03: brackets_03::BracketsApplyPrefixPass,
    pub b04: brackets_04::BracketsHistogramLayersPass,
    pub b05: brackets_05::BracketsScanHistogramsPass,
    pub b06: brackets_06::BracketsScatterByLayerPass,
    pub pse04: brackets_pse_04::BracketsPsePairPass, // Replaces b07

    // Tree building passes (tiled stack approach)
    pub t_b1: tree_blocked_01::TreeBlockLocalPass,
    pub t_b2: tree_blocked_02::TreeStitchSeedsPass,
    pub t_b3: tree_blocked_03::TreeBlockSeededPass,
}

impl ParserPasses {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            llp_pairs: llp_pairs::LLPPairsPass::new(device)?,
            pack_varlen: pack_varlen::PackVarlenPass::new(device)?,

            b01: brackets_01::BracketsScanInblockPass::new(device)?,
            b02: brackets_02::BracketsScanBlockPrefixPass::new(device)?,
            b03: brackets_03::BracketsApplyPrefixPass::new(device)?,
            b04: brackets_04::BracketsHistogramLayersPass::new(device)?,
            b05: brackets_05::BracketsScanHistogramsPass::new(device)?,
            b06: brackets_06::BracketsScatterByLayerPass::new(device)?,
            pse04: brackets_pse_04::BracketsPsePairPass::new(device)?,

            t_b1: tree_blocked_01::TreeBlockLocalPass::new(device)?,
            t_b2: tree_blocked_02::TreeStitchSeedsPass::new(device)?,
            t_b3: tree_blocked_03::TreeBlockSeededPass::new(device)?,
        })
    }
}

/// Record the whole pipeline in order.
pub fn record_all_passes(
    mut ctx: PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1D;

    // 0) pair→header + pack
    let n_pairs = ctx.buffers.n_tokens.saturating_sub(1);
    p.llp_pairs.record_pass(&mut ctx, E1D(n_pairs))?;
    p.pack_varlen.record_pass(&mut ctx, E1D(n_pairs))?;

    // 1) Brackets (parallel)
    let n_sc = ctx.buffers.total_sc;
    let n_blocks = ctx.buffers.b_n_blocks;
    let n_layers = ctx.buffers.b_n_layers;

    // Bracket matching - depth computation (same as before)
    p.b01.record_pass(&mut ctx, E1D(n_sc))?;
    p.b02.record_pass(&mut ctx, E1D(n_blocks))?;
    p.b03.record_pass(&mut ctx, E1D(n_sc))?;

    // Bracket matching - PSE-style pairing
    p.b04.record_pass(&mut ctx, E1D(n_sc))?; // Histogram layers
    p.b05.record_pass(&mut ctx, E1D(n_layers))?; // Prefix sum over histograms

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
    p.pse04.record_pass(&mut ctx, E1D(n_layers))?; // PSE-style pairing

    // Tiled tree building
    let n_emit = ctx.buffers.total_emit;
    let n_blocks_tb = ((n_emit + 1023) / 1024).max(1);

    // TB1: Local stack within blocks
    p.t_b1.record_pass(&mut ctx, E1D(n_blocks_tb))?;

    // TB2: Stitch block summaries (single thread)
    p.t_b2.record_pass(&mut ctx, E1D(1))?;

    // TB3: Final tree build with seeded stacks
    p.t_b3.record_pass(&mut ctx, E1D(n_blocks_tb))?;

    Ok(())
}
