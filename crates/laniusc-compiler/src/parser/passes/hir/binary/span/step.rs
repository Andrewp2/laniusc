use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData},
    parser::{buffers::ParserBuffers, passes::hir::list::rank::step::list_rank_step_capacity},
};

/// Bounded-walk pass that propagates binary-expression span starts over the
/// compacted rows whose left chain outlived the seed's local walk.
pub struct HirBinarySpanStepPass {
    data: PassData,
}

pub(in crate::parser) const A_TO_B: &str = "hir_binary_span_step.a_to_b";
pub(in crate::parser) const B_TO_A: &str = "hir_binary_span_step.b_to_a";

crate::gpu::passes_core::impl_static_shader_pass!(
    HirBinarySpanStepPass,
    label: "hir_binary_span_step",
    shader: "parser/hir/binary/span/step"
);

/// Bounded-walk steps for a tree of `items` nodes: always even, so the
/// result ends in the A buffers.
pub(in crate::parser) fn binary_span_step_capacity(items: u32) -> u32 {
    list_rank_step_capacity(items)
}

impl HirBinarySpanStepPass {
    /// Records binary-span propagation steps with indirect dispatch.
    pub fn record_steps_indirect(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let steps = binary_span_step_capacity(buffers.tree_capacity);
        for step in 0..steps {
            self.record_step(device, encoder, buffers, step, dispatch_args, cache)?;
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        step: u32,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let read_a = step % 2 == 0;
        let (link_in, start_in, link_out, start_out) = if read_a {
            (
                &buffers.hir_binary_span_link_a,
                &buffers.hir_binary_span_start_a,
                &buffers.hir_binary_span_link_b,
                &buffers.hir_binary_span_start_b,
            )
        } else {
            (
                &buffers.hir_binary_span_link_b,
                &buffers.hir_binary_span_start_b,
                &buffers.hir_binary_span_link_a,
                &buffers.hir_binary_span_start_a,
            )
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gHirExpr".into(),
                buffers.hir_expr_fields_params.as_entire_binding(),
            ),
            (
                "hir_semantic_count".into(),
                buffers.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_list_rank_node".into(),
                buffers.hir_list_rank_node.as_entire_binding(),
            ),
            (
                "hir_list_rank_count".into(),
                buffers.hir_list_rank_count.as_entire_binding(),
            ),
            (
                "hir_binary_span_link_in".into(),
                link_in.as_entire_binding(),
            ),
            (
                "hir_binary_span_start_in".into(),
                start_in.as_entire_binding(),
            ),
            (
                "hir_binary_span_link_out".into(),
                link_out.as_entire_binding(),
            ),
            (
                "hir_binary_span_start_out".into(),
                start_out.as_entire_binding(),
            ),
        ]);

        let label = if read_a { A_TO_B } else { B_TO_A };
        let invocation = format!("{label}.{step}");
        let bind_group = cache
            .reflected_for_graph_invocation(
                device,
                &invocation,
                label,
                &self.data,
                buffers,
                &resources,
                Some(dispatch_args),
            )?
            .into_iter()
            .next()
            .expect("binary-span step must have one reflected bind group");
        crate::gpu::passes_core::record_or_defer_compute_indirect(
            encoder,
            &self.data,
            bind_group.as_ref(),
            label,
            dispatch_args,
        );
        Ok(())
    }

    pub(in crate::parser) fn graph_pass(&self) -> &PassData {
        &self.data
    }
}

#[cfg(test)]
mod tests {
    use super::binary_span_step_capacity;

    #[test]
    fn steps_are_even_and_cover_any_chain_with_sixteen_links_each() {
        for items in [0, 1, 2, 16, 17, 256, 257, 4_096, 1_687_524, u32::MAX] {
            let steps = binary_span_step_capacity(items);
            assert_eq!(steps % 2, 0);
            assert!(16u128.pow(steps) >= u128::from(items.max(1)));
        }
        assert_eq!(binary_span_step_capacity(1_687_524), 6);
    }
}
