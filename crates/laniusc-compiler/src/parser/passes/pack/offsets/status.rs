use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::{
        buffers::{LaniusBuffer, uniform_from_val},
        passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    },
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for packed stream status validation.
pub struct Params {
    pub n_pairs: u32,
    pub emit_capacity: u32,
}

/// Pass that validates partial-parse packed stream capacity and status.
pub struct PackOffsetsStatusPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    PackOffsetsStatusPass,
    label: "pack_offsets_status",
    shader: "parser/pack/offsets/status"
);

impl PackOffsetsStatusPass {
    /// Records direct status validation for packed stream offsets.
    pub fn record_pass(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        self.record_pass_inner(device, encoder, buffers, None)
    }

    /// Records indirect status validation for packed stream offsets.
    pub fn record_pass_indirect(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<()> {
        self.record_pass_inner(device, encoder, buffers, Some(dispatch_args))
    }

    fn record_pass_inner(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: Option<&wgpu::Buffer>,
    ) -> Result<()> {
        let n_pairs = buffers.n_tokens.saturating_sub(1);
        let params: LaniusBuffer<Params> = uniform_from_val(
            device,
            "pack.offset_status.params",
            &Params {
                n_pairs,
                emit_capacity: buffers.tree_capacity,
            },
        );
        let read_from_a = buffers
            .pack_offset_scan_steps
            .last()
            .map(|step| step.read_from_a)
            .unwrap_or(true);
        let sc_prefix = if read_from_a {
            &buffers.pack_sc_prefix_a
        } else {
            &buffers.pack_sc_prefix_b
        };
        let emit_prefix = if read_from_a {
            &buffers.pack_emit_prefix_a
        } else {
            &buffers.pack_emit_prefix_b
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), params.as_entire_binding()),
            (
                "token_count".into(),
                buffers.token_count.as_entire_binding(),
            ),
            ("sc_prefix".into(), sc_prefix.as_entire_binding()),
            ("emit_prefix".into(), emit_prefix.as_entire_binding()),
            (
                "partial_parse_status".into(),
                buffers.partial_parse_status.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("pack_offsets_status"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        let [tgsx, tgsy, _] = self.data.thread_group_size;
        if let Some(dispatch_args) = dispatch_args {
            crate::gpu::passes_core::record_or_defer_compute_indirect(
                encoder,
                &self.data,
                &bind_group,
                "pack_offsets_status",
                dispatch_args,
            );
        } else {
            let groups = plan_workgroups(
                DispatchDim::D1,
                InputElements::Elements1D(n_pairs.max(1)),
                [tgsx, tgsy, 1],
            )?;
            crate::gpu::passes_core::record_or_defer_compute_direct(
                encoder,
                &self.data,
                &bind_group,
                "pack_offsets_status",
                groups,
            );
        }
        Ok(())
    }
}
