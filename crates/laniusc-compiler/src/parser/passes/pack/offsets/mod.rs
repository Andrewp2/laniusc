//! Hierarchical prefix scan for packed parser pair streams.

/// Status validation for packed parser offset scans.
pub mod status;

use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{
        BindGroupCache,
        DispatchDim,
        InputElements,
        PassData,
        make_pass_data_from_shader_key,
        plan_workgroups,
    },
    parser::buffers::{PackOffsetHierarchyStep, ParserBuffers},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Capacity parameters for the paired stack-change/emit scan.
pub struct Params {
    pub n_pairs: u32,
    pub n_blocks: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// One level of the paired offset-scan hierarchy.
pub struct HierarchyParams {
    pub n_items: u32,
    pub n_blocks: u32,
    pub level_divisor: u32,
    pub level_offset: u32,
    pub parent_divisor: u32,
    pub parent_offset: u32,
}

/// Paired 256-way hierarchical scan that publishes both packed-stream offsets.
pub struct PackOffsetsScanPass {
    local: PassData,
    hierarchy_up: PassData,
    hierarchy_down: PassData,
    apply: PassData,
}

impl PackOffsetsScanPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let pass = |label, shader| make_pass_data_from_shader_key(device, label, "main", shader);
        Ok(Self {
            local: pass("pack_offsets_scan.local", "parser/pack/offsets/scan")?,
            hierarchy_up: pass(
                "pack_offsets_scan.hierarchy_up",
                "parser/pack/offsets/hierarchy_up",
            )?,
            hierarchy_down: pass(
                "pack_offsets_scan.hierarchy_down",
                "parser/pack/offsets/hierarchy_down",
            )?,
            apply: pass("pack_offsets_scan.apply", "parser/pack/offsets/apply")?,
        })
    }

    pub(in crate::parser) fn graph_passes(&self) -> (&PassData, &PassData, &PassData, &PassData) {
        (
            &self.local,
            &self.hierarchy_up,
            &self.hierarchy_down,
            &self.apply,
        )
    }

    /// Records the paired scan with GPU-produced local/apply dispatches.
    pub fn record_scan_indirect(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
    ) -> Result<()> {
        // LLP action headers are produced by the preceding dispatch. The scan
        // consumes them through a separately constructed operation, so make
        // the storage dependency explicit instead of relying on deferred-pass
        // hazard inference across operation boundaries.
        crate::gpu::passes_core::flush_deferred_compute(encoder);
        let common = || {
            HashMap::from([
                (
                    "token_count".into(),
                    buffers.token_count.as_entire_binding(),
                ),
                (
                    "sc_workspace".into(),
                    buffers.pack_sc_prefix_a.as_entire_binding(),
                ),
                (
                    "emit_workspace".into(),
                    buffers.pack_emit_prefix_a.as_entire_binding(),
                ),
                (
                    "sc_block_prefix".into(),
                    buffers.pack_sc_prefix_b.as_entire_binding(),
                ),
                (
                    "emit_block_prefix".into(),
                    buffers.pack_emit_prefix_b.as_entire_binding(),
                ),
            ])
        };

        let mut local_resources = common();
        local_resources.extend([
            (
                "gParams".into(),
                buffers.pack_offset_scan_plan.params.as_entire_binding(),
            ),
            (
                "out_headers".into(),
                buffers.out_headers.as_entire_binding(),
            ),
            ("sc_offsets".into(), buffers.sc_offsets.as_entire_binding()),
            (
                "emit_offsets".into(),
                buffers.emit_offsets.as_entire_binding(),
            ),
        ]);
        let local_operation = crate::parser::compiler_graph::PACK_OFFSETS_LOCAL;
        let local = reflected_group(
            device,
            cache,
            buffers,
            &self.local,
            local_operation,
            local_operation,
            &local_resources,
            Some(dispatch_args),
        )?;
        self.record_end_pass(encoder, &self.local, &local, local_operation, dispatch_args)?;
        crate::gpu::passes_core::flush_deferred_compute(encoder);

        for (index, step) in buffers.pack_offset_scan_plan.up.iter().enumerate() {
            self.record_hierarchy(
                device,
                encoder,
                cache,
                buffers,
                &self.hierarchy_up,
                "pack_offsets_scan.hierarchy_up",
                index,
                step,
                common(),
            )?;
            crate::gpu::passes_core::flush_deferred_compute(encoder);
        }
        for (index, step) in buffers.pack_offset_scan_plan.down.iter().enumerate() {
            self.record_hierarchy(
                device,
                encoder,
                cache,
                buffers,
                &self.hierarchy_down,
                "pack_offsets_scan.hierarchy_down",
                index,
                step,
                common(),
            )?;
            crate::gpu::passes_core::flush_deferred_compute(encoder);
        }

        let mut apply_resources = common();
        apply_resources.extend([
            (
                "gParams".into(),
                buffers.pack_offset_scan_plan.params.as_entire_binding(),
            ),
            ("sc_offsets".into(), buffers.sc_offsets.as_entire_binding()),
            (
                "emit_offsets".into(),
                buffers.emit_offsets.as_entire_binding(),
            ),
        ]);
        let apply_operation = crate::parser::compiler_graph::PACK_OFFSETS_APPLY;
        let apply = reflected_group(
            device,
            cache,
            buffers,
            &self.apply,
            apply_operation,
            apply_operation,
            &apply_resources,
            Some(dispatch_args),
        )?;
        self.record_end_pass(encoder, &self.apply, &apply, apply_operation, dispatch_args)?;
        crate::gpu::passes_core::flush_deferred_compute(encoder);
        Ok(())
    }

    fn record_hierarchy<'a>(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        cache: &mut BindGroupCache,
        buffers: &ParserBuffers,
        pass: &PassData,
        label: &'static str,
        index: usize,
        step: &'a PackOffsetHierarchyStep,
        mut resources: HashMap<String, wgpu::BindingResource<'a>>,
    ) -> Result<()> {
        resources.insert("gHierarchy".into(), step.params.as_entire_binding());
        let invocation = format!("{label}.{index}");
        let group = reflected_group(
            device,
            cache,
            buffers,
            pass,
            &invocation,
            label,
            &resources,
            None,
        )?;
        let [x, y, _] = pass.thread_group_size;
        let groups = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(step.work_items),
            [x, y, 1],
        )?;
        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder, pass, &group, label, groups,
        );
        Ok(())
    }

    fn record_end_pass(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pass: &PassData,
        group: &wgpu::BindGroup,
        label: &'static str,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
    ) -> Result<()> {
        crate::gpu::passes_core::record_or_defer_compute_indirect(
            encoder,
            pass,
            group,
            label,
            dispatch_args,
        );
        Ok(())
    }
}

fn reflected_group(
    device: &wgpu::Device,
    cache: &mut BindGroupCache,
    buffers: &ParserBuffers,
    pass: &PassData,
    invocation: &str,
    operation: &'static str,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
    dispatch_args: Option<&crate::gpu::buffers::LaniusBuffer<u32>>,
) -> Result<std::sync::Arc<wgpu::BindGroup>> {
    Ok(cache
        .reflected_for_graph_invocation(
            device,
            invocation,
            operation,
            pass,
            buffers,
            resources,
            dispatch_args,
        )?
        .into_iter()
        .next()
        .expect("pack offset scan pass must have one reflected bind group"))
}
