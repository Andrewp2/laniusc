use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::{
        buffers::{LaniusBuffer, uniform_from_val},
        passes_core::{PassData, bind_group},
    },
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for validating packed stream totals against capacity.
pub struct Params {
    pub n_pairs: u32,
    pub emit_capacity: u32,
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
    /// Records the final packed-total status pass.
    pub fn record_pass(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        let n_pairs = buffers.n_tokens.saturating_sub(1);
        let params: LaniusBuffer<Params> = uniform_from_val(
            device,
            "pack.totals_status.params",
            &Params {
                n_pairs,
                emit_capacity: buffers.tree_capacity,
            },
        );
        let read_from_a = buffers
            .pack_total_reduce_steps
            .last()
            .map(|step| step.write_to_a)
            .unwrap_or(true);
        let sc_total = if read_from_a {
            &buffers.pack_sc_prefix_a
        } else {
            &buffers.pack_sc_prefix_b
        };
        let emit_total = if read_from_a {
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
            ("sc_total".into(), sc_total.as_entire_binding()),
            ("emit_total".into(), emit_total.as_entire_binding()),
            (
                "partial_parse_status".into(),
                buffers.partial_parse_status.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("pack_totals_status"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder,
            &self.data,
            &bind_group,
            "pack_totals_status",
            (1, 1, 1),
        );
        Ok(())
    }
}
