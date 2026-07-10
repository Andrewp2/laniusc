//! Prefix-scan passes for packed parser pair streams.

/// Status validation for packed parser offset scans.
pub mod status;

use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    parser::buffers::{PackOffsetScanStep, ParserBuffers},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for packed stream offset scans.
pub struct Params {
    pub n_pairs: u32,
    pub scan_step: u32,
}

/// Pass that scans stack-change and emit lengths into packed stream offsets.
pub struct PackOffsetsScanPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    PackOffsetsScanPass,
    label: "pack_offsets_scan",
    shader: "parser/pack/offsets/scan"
);

impl PackOffsetsScanPass {
    /// Records all configured offset scan steps.
    pub fn record_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        for step in &buffers.pack_offset_scan_steps {
            self.record_step(device, encoder, buffers, step, None)?;
        }
        Ok(())
    }

    /// Records all offset scan steps with indirect dispatch arguments.
    pub fn record_scan_indirect(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<()> {
        for step in &buffers.pack_offset_scan_steps {
            self.record_step(device, encoder, buffers, step, Some(dispatch_args))?;
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        step: &PackOffsetScanStep,
        dispatch_args: Option<&wgpu::Buffer>,
    ) -> Result<()> {
        let sc_prefix_in = if step.read_from_a {
            &buffers.pack_sc_prefix_a
        } else {
            &buffers.pack_sc_prefix_b
        };
        let sc_prefix_out = if step.write_to_a {
            &buffers.pack_sc_prefix_a
        } else {
            &buffers.pack_sc_prefix_b
        };
        let emit_prefix_in = if step.read_from_a {
            &buffers.pack_emit_prefix_a
        } else {
            &buffers.pack_emit_prefix_b
        };
        let emit_prefix_out = if step.write_to_a {
            &buffers.pack_emit_prefix_a
        } else {
            &buffers.pack_emit_prefix_b
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step.params.as_entire_binding()),
            (
                "token_count".into(),
                buffers.token_count.as_entire_binding(),
            ),
            (
                "out_headers".into(),
                buffers.out_headers.as_entire_binding(),
            ),
            ("sc_prefix_in".into(), sc_prefix_in.as_entire_binding()),
            ("emit_prefix_in".into(), emit_prefix_in.as_entire_binding()),
            ("sc_prefix_out".into(), sc_prefix_out.as_entire_binding()),
            (
                "emit_prefix_out".into(),
                emit_prefix_out.as_entire_binding(),
            ),
            ("sc_offsets".into(), buffers.sc_offsets.as_entire_binding()),
            (
                "emit_offsets".into(),
                buffers.emit_offsets.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("pack_offsets_scan"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        if let Some(dispatch_args) = dispatch_args {
            crate::gpu::passes_core::record_or_defer_compute_indirect(
                encoder,
                &self.data,
                &bind_group,
                "pack_offsets_scan",
                dispatch_args,
            );
        } else {
            let [tgsx, tgsy, _] = self.data.thread_group_size;
            let groups = plan_workgroups(
                DispatchDim::D1,
                InputElements::Elements1D(buffers.n_tokens.saturating_sub(1)),
                [tgsx, tgsy, 1],
            )?;
            crate::gpu::passes_core::record_or_defer_compute_direct(
                encoder,
                &self.data,
                &bind_group,
                "pack_offsets_scan",
                groups,
            );
        }
        Ok(())
    }
}
