use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData},
    parser::buffers::ParserBuffers,
};

/// Pointer-jump pass that propagates binary-expression span starts.
pub struct HirBinarySpanStepPass {
    data: PassData,
}

pub(in crate::parser) const A_TO_B: &str = "hir_binary_span_step.a_to_b";
pub(in crate::parser) const B_TO_A: &str = "hir_binary_span_step.b_to_a";
pub(in crate::parser) const A_TO_B_FINAL: &str = "hir_binary_span_step.a_to_b_final";
pub(in crate::parser) const FINALIZE: &str = "hir_binary_span_step.finalize";

crate::gpu::passes_core::impl_static_shader_pass!(
    HirBinarySpanStepPass,
    label: "hir_binary_span_step",
    shader: "parser/hir/binary/span/step"
);

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
        let steps = pointer_jump_steps_for_items(buffers.tree_capacity);
        for step in 0..steps {
            self.record_step(
                device,
                encoder,
                buffers,
                step,
                step % 2 == 0,
                step + 1 == steps && steps % 2 == 1,
                dispatch_args,
                cache,
            )?;
        }

        if steps % 2 == 1 {
            buffers.record_finalizer(FINALIZE, encoder)?;
        }

        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        step: u32,
        read_from_a: bool,
        final_unpaired_step: bool,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let (link_in, start_in, link_out, start_out) = if read_from_a {
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

        let label = if final_unpaired_step {
            A_TO_B_FINAL
        } else if read_from_a {
            A_TO_B
        } else {
            B_TO_A
        };
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

pub(in crate::parser) fn pointer_jump_steps_for_items(items: u32) -> u32 {
    crate::parser::buffers::pointer_jump_step_capacity(items.max(1).div_ceil(32))
}

#[cfg(test)]
mod tests {
    use super::pointer_jump_steps_for_items;

    #[test]
    fn bounded_local_compression_preserves_arbitrary_chain_coverage() {
        for items in [0, 1, 31, 32, 33, 64, 65, 4_096, 1_687_524, u32::MAX] {
            let steps = pointer_jump_steps_for_items(items);
            let covered = 32u64 << steps;
            assert!(covered >= u64::from(items.max(1)));
            if steps != 0 {
                assert!((covered / 2) < u64::from(items.max(1)));
            }
        }
        assert_eq!(pointer_jump_steps_for_items(1_687_524), 16);
    }
}
