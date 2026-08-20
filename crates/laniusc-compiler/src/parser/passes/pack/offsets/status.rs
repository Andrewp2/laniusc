use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for packed stream status validation.
pub(crate) struct Params {
    pub(crate) n_pairs: u32,
    pub(crate) emit_capacity: u32,
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
    pub(in crate::parser) fn data(&self) -> &PassData {
        &self.data
    }

    /// Records indirect status validation for packed stream offsets.
    pub fn record_pass_indirect(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
    ) -> Result<()> {
        let n_pairs = buffers.n_tokens.saturating_sub(1);
        crate::parser::buffers::write_uniform(
            queue,
            &buffers.pack_offsets_status_params,
            &Params {
                n_pairs,
                emit_capacity: buffers.tree_capacity,
            },
        );
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                buffers.pack_offsets_status_params.as_entire_binding(),
            ),
            (
                "token_count".into(),
                buffers.token_count.as_entire_binding(),
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
            (
                "partial_parse_status".into(),
                buffers.partial_parse_status.as_entire_binding(),
            ),
            (
                "active_stack_thread_dispatch_args".into(),
                buffers
                    .active_stack_thread_dispatch_args
                    .as_entire_binding(),
            ),
        ]);
        let operation = crate::parser::compiler_graph::PACK_OFFSETS_STATUS;
        let bind_group = cache
            .reflected_for_graph_pass_data(
                device,
                operation,
                &self.data,
                buffers,
                &resources,
                Some(dispatch_args),
            )?
            .into_iter()
            .next()
            .expect("pack offset status pass must have one reflected bind group");
        crate::gpu::passes_core::record_or_defer_compute_indirect(
            encoder,
            &self.data,
            bind_group.as_ref(),
            operation,
            dispatch_args,
        );
        Ok(())
    }
}
