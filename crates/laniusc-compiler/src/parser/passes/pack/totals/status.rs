use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for validating packed stream totals against capacity.
pub struct Params {
    pub n_pairs: u32,
    pub emit_capacity: u32,
    pub read_from_a: u32,
}

/// Pass that writes parser pack-total status words.
pub struct PackTotalsStatusPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    PackTotalsStatusPass,
    label: "pack_totals_status",
    shader: "parser/pack/totals/status"
);

impl PackTotalsStatusPass {
    pub(in crate::parser) fn data(&self) -> &PassData {
        &self.data
    }

    /// Records the final packed-total status pass.
    pub fn record_pass(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                buffers.pack_totals_status_params.as_entire_binding(),
            ),
            (
                "token_count".into(),
                buffers.token_count.as_entire_binding(),
            ),
            (
                "sc_total_a".into(),
                buffers.pack_sc_prefix_a.as_entire_binding(),
            ),
            (
                "sc_total_b".into(),
                buffers.pack_sc_prefix_b.as_entire_binding(),
            ),
            (
                "emit_total_a".into(),
                buffers.pack_emit_prefix_a.as_entire_binding(),
            ),
            (
                "emit_total_b".into(),
                buffers.pack_emit_prefix_b.as_entire_binding(),
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
        let bind_group = cache
            .reflected_for_graph_pass_data(
                device,
                crate::parser::compiler_graph::PACK_TOTALS_STATUS,
                &self.data,
                buffers,
                &resources,
                None,
            )?
            .into_iter()
            .next()
            .expect("pack totals status pass must have one reflected bind group");
        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder,
            &self.data,
            bind_group.as_ref(),
            crate::parser::compiler_graph::PACK_TOTALS_STATUS,
            (1, 1, 1),
        );
        Ok(())
    }
}
