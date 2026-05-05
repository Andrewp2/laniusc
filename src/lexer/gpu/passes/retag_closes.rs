use std::collections::HashMap;

use anyhow::Result;

use super::PassData;
use crate::{
    gpu::passes_core::{DispatchDim, InputElements, Pass, PassContext},
    lexer::gpu::{buffers::GpuBuffers, debug::DebugOutput},
};

macro_rules! retag_pass {
    ($name:ident, $entry:literal, $label:literal, |$b:ident| {$($res_name:literal => $res_expr:expr),+ $(,)?}) => {
        struct $name {
            data: PassData,
        }

        impl $name {
            fn new(device: &wgpu::Device) -> Result<Self> {
                let data = crate::gpu::passes_core::make_pass_data(
                    device,
                    $label,
                    $entry,
                    include_bytes!(concat!(env!("OUT_DIR"), "/shaders/", $label, ".spv")),
                    include_bytes!(concat!(
                        env!("OUT_DIR"),
                        "/shaders/",
                        $label,
                        ".reflect.json"
                    )),
                )?;
                Ok(Self { data })
            }
        }

        impl Pass<GpuBuffers, DebugOutput> for $name {
            const NAME: &'static str = $label;
            const DIM: DispatchDim = DispatchDim::D1;

            fn from_data(data: PassData) -> Self {
                Self { data }
            }

            fn data(&self) -> &PassData {
                &self.data
            }

            fn create_resource_map<'a>(
                &self,
                $b: &'a GpuBuffers,
            ) -> HashMap<String, wgpu::BindingResource<'a>> {
                HashMap::from([
                    $(
                        ($res_name.into(), $res_expr),
                    )+
                ])
            }
        }
    };
}

retag_pass!(
    RetagClosesScanPass,
    "main",
    "retag_closes_01_scan",
    |b| {
        "token_count" => b.token_count.as_entire_binding(),
        "tokens_out" => b.tokens_out.as_entire_binding(),
        "exscan_inblock" => b.close_exscan_inblock.as_entire_binding(),
        "block_sum" => b.close_block_sum.as_entire_binding(),
    }
);

retag_pass!(
    RetagClosesScanBlocksPass,
    "main",
    "retag_closes_02_scan_blocks",
    |b| {
        "gParams" => wgpu::BindingResource::Buffer(b.params.as_entire_buffer_binding()),
        "block_sum" => b.close_block_sum.as_entire_binding(),
        "block_prefix" => b.close_block_prefix.as_entire_binding(),
    }
);

retag_pass!(
    RetagClosesHistogramPass,
    "main",
    "retag_closes_03_histogram",
    |b| {
        "token_count" => b.token_count.as_entire_binding(),
        "tokens_out" => b.tokens_out.as_entire_binding(),
        "exscan_inblock" => b.close_exscan_inblock.as_entire_binding(),
        "block_prefix" => b.close_block_prefix.as_entire_binding(),
        "layer" => b.close_layer.as_entire_binding(),
        "hist_push" => b.close_hist_push.as_entire_binding(),
        "hist_pop" => b.close_hist_pop.as_entire_binding(),
    }
);

retag_pass!(
    RetagClosesScanHistogramsPass,
    "main",
    "retag_closes_04_scan_histograms",
    |b| {
        "token_count" => b.token_count.as_entire_binding(),
        "hist_push" => b.close_hist_push.as_entire_binding(),
        "hist_pop" => b.close_hist_pop.as_entire_binding(),
        "off_push" => b.close_off_push.as_entire_binding(),
        "off_pop" => b.close_off_pop.as_entire_binding(),
    }
);

retag_pass!(
    RetagClosesRankPass,
    "main",
    "retag_closes_05_rank",
    |b| {
        "token_count" => b.token_count.as_entire_binding(),
        "tokens_out" => b.tokens_out.as_entire_binding(),
        "layer" => b.close_layer.as_entire_binding(),
        "hist_push" => b.close_hist_push.as_entire_binding(),
        "hist_pop" => b.close_hist_pop.as_entire_binding(),
        "rank" => b.close_rank.as_entire_binding(),
    }
);

retag_pass!(
    RetagClosesScatterPass,
    "main",
    "retag_closes_06_scatter",
    |b| {
        "token_count" => b.token_count.as_entire_binding(),
        "tokens_out" => b.tokens_out.as_entire_binding(),
        "layer" => b.close_layer.as_entire_binding(),
        "rank" => b.close_rank.as_entire_binding(),
        "off_push" => b.close_off_push.as_entire_binding(),
        "off_pop" => b.close_off_pop.as_entire_binding(),
        "pushes_by_layer" => b.close_pushes_by_layer.as_entire_binding(),
        "pops_by_layer" => b.close_pops_by_layer.as_entire_binding(),
    }
);

retag_pass!(
    RetagClosesApplyPass,
    "main",
    "retag_closes_07_apply",
    |b| {
        "token_count" => b.token_count.as_entire_binding(),
        "tokens_out" => b.tokens_out.as_entire_binding(),
        "hist_push" => b.close_hist_push.as_entire_binding(),
        "hist_pop" => b.close_hist_pop.as_entire_binding(),
        "off_push" => b.close_off_push.as_entire_binding(),
        "off_pop" => b.close_off_pop.as_entire_binding(),
        "pushes_by_layer" => b.close_pushes_by_layer.as_entire_binding(),
        "pops_by_layer" => b.close_pops_by_layer.as_entire_binding(),
    }
);

pub struct RetagClosesPasses {
    scan: RetagClosesScanPass,
    scan_blocks: RetagClosesScanBlocksPass,
    histogram: RetagClosesHistogramPass,
    scan_histograms: RetagClosesScanHistogramsPass,
    rank: RetagClosesRankPass,
    scatter: RetagClosesScatterPass,
    apply: RetagClosesApplyPass,
}

impl RetagClosesPasses {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            scan: RetagClosesScanPass::new(device)?,
            scan_blocks: RetagClosesScanBlocksPass::new(device)?,
            histogram: RetagClosesHistogramPass::new(device)?,
            scan_histograms: RetagClosesScanHistogramsPass::new(device)?,
            rank: RetagClosesRankPass::new(device)?,
            scatter: RetagClosesScatterPass::new(device)?,
            apply: RetagClosesApplyPass::new(device)?,
        })
    }

    pub fn record_all<'a>(
        &self,
        ctx: &mut PassContext<'a, GpuBuffers, DebugOutput>,
        n: u32,
        nb_sum: u32,
    ) -> Result<()> {
        ctx.encoder
            .clear_buffer(&ctx.buffers.close_hist_push, 0, None);
        ctx.encoder
            .clear_buffer(&ctx.buffers.close_hist_pop, 0, None);

        self.scan.record_pass(ctx, InputElements::Elements1D(n))?;
        self.scan_blocks
            .record_pass(ctx, InputElements::Elements1D(nb_sum))?;
        self.histogram
            .record_pass(ctx, InputElements::Elements1D(n))?;
        self.scan_histograms
            .record_pass(ctx, InputElements::Elements1D(n.saturating_add(2)))?;
        self.rank
            .record_pass(ctx, InputElements::Elements1D(n.saturating_add(2)))?;
        self.scatter
            .record_pass(ctx, InputElements::Elements1D(n))?;
        self.apply
            .record_pass(ctx, InputElements::Elements1D(n.saturating_add(2)))?;

        if let Some(dbg) = ctx.maybe_dbg.as_deref_mut() {
            dbg.gpu.tokens_out.set_from_copy(
                ctx.device,
                ctx.encoder,
                &ctx.buffers.tokens_out,
                "dbg.tokens_out",
                ctx.buffers.tokens_out.byte_size,
            );
        }

        Ok(())
    }
}
