use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{BindGroupCache, DispatchDim, InputElements, PassData, plan_workgroups},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for bracket block-prefix finalization.
pub struct Params {
    pub n_blocks: u32,
    pub scan_step: u32,
}

/// Hierarchically scans bracket block summaries and finalizes global depths.
pub struct BracketsScanBlockPrefixPass {
    up: PassData,
    down: PassData,
    finalize: PassData,
}

impl BracketsScanBlockPrefixPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            up: crate::gpu::passes_core::make_main_pass!(
                device,
                "brackets_02_scan_block_prefix_up",
                shader: "parser/brackets/02_scan_up"
            )?,
            down: crate::gpu::passes_core::make_main_pass!(
                device,
                "brackets_02_scan_block_prefix_down",
                shader: "parser/brackets/02_scan_down"
            )?,
            finalize: crate::gpu::passes_core::make_main_pass!(
                device,
                "brackets_02_scan_block_prefix",
                shader: "parser/brackets/02_scan_block_prefix"
            )?,
        })
    }

    pub(in crate::parser) fn graph_passes(&self) -> (&PassData, &PassData, &PassData) {
        (&self.up, &self.down, &self.finalize)
    }

    /// Records the hierarchy reduction, carry propagation, and finalization.
    pub fn record_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        for (index, step) in buffers.b02_scan_plan.up.iter().enumerate() {
            let resources = HashMap::from([
                ("gBracketScan".into(), step.params.as_entire_binding()),
                ("block_sum".into(), buffers.b_block_sum.as_entire_binding()),
                (
                    "block_minpref".into(),
                    buffers.b_block_minpref.as_entire_binding(),
                ),
                (
                    "prefix_sum".into(),
                    buffers.b_block_prefix_sum_a.as_entire_binding(),
                ),
                (
                    "prefix_min".into(),
                    buffers.b_block_prefix_min_a.as_entire_binding(),
                ),
                (
                    "hierarchy_sum".into(),
                    buffers.b_block_prefix_sum_b.as_entire_binding(),
                ),
                (
                    "hierarchy_min".into(),
                    buffers.b_block_prefix_min_b.as_entire_binding(),
                ),
            ]);
            self.record_step(
                device,
                encoder,
                cache,
                buffers,
                &self.up,
                &format!("brackets_02_scan_block_prefix_up.{index}"),
                crate::parser::compiler_graph::BRACKET_SCAN_UP,
                &resources,
                step.work_items,
            )?;
        }

        for (index, step) in buffers.b02_scan_plan.down.iter().enumerate() {
            let resources = HashMap::from([
                ("gBracketScan".into(), step.params.as_entire_binding()),
                (
                    "prefix_sum".into(),
                    buffers.b_block_prefix_sum_a.as_entire_binding(),
                ),
                (
                    "prefix_min".into(),
                    buffers.b_block_prefix_min_a.as_entire_binding(),
                ),
                (
                    "hierarchy_sum".into(),
                    buffers.b_block_prefix_sum_b.as_entire_binding(),
                ),
                (
                    "hierarchy_min".into(),
                    buffers.b_block_prefix_min_b.as_entire_binding(),
                ),
            ]);
            self.record_step(
                device,
                encoder,
                cache,
                buffers,
                &self.down,
                &format!("brackets_02_scan_block_prefix_down.{index}"),
                crate::parser::compiler_graph::BRACKET_SCAN_DOWN,
                &resources,
                step.work_items,
            )?;
        }

        let resources = HashMap::from([
            ("gParams".into(), buffers.b02_params.as_entire_binding()),
            ("block_sum".into(), buffers.b_block_sum.as_entire_binding()),
            (
                "block_maxdepth".into(),
                buffers.b_block_maxdepth.as_entire_binding(),
            ),
            (
                "prefix_sum".into(),
                buffers.b_block_prefix_sum_a.as_entire_binding(),
            ),
            (
                "prefix_min".into(),
                buffers.b_block_prefix_min_a.as_entire_binding(),
            ),
            (
                "block_prefix".into(),
                buffers.b_block_prefix.as_entire_binding(),
            ),
            ("out_depths".into(), buffers.depths_out.as_entire_binding()),
            ("out_valid".into(), buffers.valid_out.as_entire_binding()),
        ]);
        self.record_step(
            device,
            encoder,
            cache,
            buffers,
            &self.finalize,
            "brackets_02_scan_block_prefix.finalize",
            crate::parser::compiler_graph::BRACKET_SCAN_FINALIZE,
            &resources,
            buffers.b_n_blocks,
        )
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        cache: &mut BindGroupCache,
        buffers: &ParserBuffers,
        pass: &PassData,
        bind_group_label: &str,
        operation: &'static str,
        resources: &HashMap<String, wgpu::BindingResource<'_>>,
        work_items: u32,
    ) -> Result<()> {
        let bind_group = cache
            .reflected_for_graph_invocation(
                device,
                bind_group_label,
                operation,
                pass,
                buffers,
                resources,
                None,
            )?
            .into_iter()
            .next()
            .expect("bracket scan pass must have one reflected bind group");
        let [tgsx, tgsy, _] = pass.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(work_items),
            [tgsx, tgsy, 1],
        )?;
        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder,
            pass,
            bind_group.as_ref(),
            operation,
            (gx, gy, gz),
        );
        Ok(())
    }
}
