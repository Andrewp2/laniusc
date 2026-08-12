//! Hierarchical prefix scan for packed parser pair streams.

/// Status validation for packed parser offset scans.
pub mod status;

use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{
        DispatchDim,
        InputElements,
        PassData,
        bind_group,
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

    /// Records the paired scan with direct local/apply dispatches.
    pub fn record_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        self.record_scan_inner(device, encoder, buffers, None)
    }

    /// Records the paired scan with GPU-produced local/apply dispatches.
    pub fn record_scan_indirect(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<()> {
        self.record_scan_inner(device, encoder, buffers, Some(dispatch_args))
    }

    fn record_scan_inner(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: Option<&wgpu::Buffer>,
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
        let local = reflected_group(
            device,
            &self.local,
            "pack_offsets_scan.local",
            &local_resources,
        )?;
        self.record_end_pass(
            encoder,
            &self.local,
            &local,
            "pack_offsets_scan.local",
            buffers,
            dispatch_args,
        )?;
        crate::gpu::passes_core::flush_deferred_compute(encoder);

        for step in &buffers.pack_offset_scan_plan.up {
            self.record_hierarchy(
                device,
                encoder,
                &self.hierarchy_up,
                "pack_offsets_scan.hierarchy_up",
                step,
                common(),
            )?;
            crate::gpu::passes_core::flush_deferred_compute(encoder);
        }
        for step in &buffers.pack_offset_scan_plan.down {
            self.record_hierarchy(
                device,
                encoder,
                &self.hierarchy_down,
                "pack_offsets_scan.hierarchy_down",
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
        let apply = reflected_group(
            device,
            &self.apply,
            "pack_offsets_scan.apply",
            &apply_resources,
        )?;
        self.record_end_pass(
            encoder,
            &self.apply,
            &apply,
            "pack_offsets_scan.apply",
            buffers,
            dispatch_args,
        )?;
        crate::gpu::passes_core::flush_deferred_compute(encoder);
        Ok(())
    }

    fn record_hierarchy<'a>(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        pass: &PassData,
        label: &'static str,
        step: &'a PackOffsetHierarchyStep,
        mut resources: HashMap<String, wgpu::BindingResource<'a>>,
    ) -> Result<()> {
        resources.insert("gHierarchy".into(), step.params.as_entire_binding());
        let group = reflected_group(device, pass, label, &resources)?;
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
        buffers: &ParserBuffers,
        dispatch_args: Option<&wgpu::Buffer>,
    ) -> Result<()> {
        if let Some(args) = dispatch_args {
            crate::gpu::passes_core::record_or_defer_compute_indirect(
                encoder, pass, group, label, args,
            );
        } else {
            let [x, y, _] = pass.thread_group_size;
            let groups = plan_workgroups(
                DispatchDim::D1,
                InputElements::Elements1D(buffers.n_tokens.saturating_sub(1)),
                [x, y, 1],
            )?;
            crate::gpu::passes_core::record_or_defer_compute_direct(
                encoder, pass, group, label, groups,
            );
        }
        Ok(())
    }
}

fn reflected_group(
    device: &wgpu::Device,
    pass: &PassData,
    label: &'static str,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
) -> Result<wgpu::BindGroup> {
    bind_group::create_bind_group_from_reflection(
        device,
        Some(label),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        resources,
    )
}
