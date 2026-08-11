use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    parser::buffers::ParserBuffers,
};

/// Pointer-jump pass that propagates binary-expression span starts.
pub struct HirBinarySpanStepPass {
    data: PassData,
}

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
        dispatch_args: &wgpu::Buffer,
    ) -> Result<()> {
        self.record_steps_inner(device, encoder, buffers, Some(dispatch_args))
    }

    /// Records binary-span propagation steps with direct dispatch.
    pub fn record_steps(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        self.record_steps_inner(device, encoder, buffers, None)
    }

    fn record_steps_inner(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: Option<&wgpu::Buffer>,
    ) -> Result<()> {
        let steps = pointer_jump_steps_for_items(buffers.tree_capacity);
        for step in 0..steps {
            self.record_step(device, encoder, buffers, step % 2 == 0, dispatch_args)?;
        }

        if steps % 2 == 1 {
            crate::gpu::passes_core::flush_deferred_compute(encoder);
            let bytes = u64::from(buffers.tree_capacity) * 4;
            for (src, dst) in [
                (
                    &buffers.hir_binary_span_link_b,
                    &buffers.hir_binary_span_link_a,
                ),
                (
                    &buffers.hir_binary_span_start_b,
                    &buffers.hir_binary_span_start_a,
                ),
            ] {
                src.copy_to(encoder, 0, dst, 0, bytes);
            }
        }

        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        read_from_a: bool,
        dispatch_args: Option<&wgpu::Buffer>,
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

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_binary_span_step"),
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
                "hir_binary_span_step",
                dispatch_args,
            );
        } else {
            let [tgsx, tgsy, _] = self.data.thread_group_size;
            let groups = plan_workgroups(
                DispatchDim::D1,
                InputElements::Elements1D(buffers.tree_capacity),
                [tgsx, tgsy, 1],
            )?;
            crate::gpu::passes_core::record_or_defer_compute_direct(
                encoder,
                &self.data,
                &bind_group,
                "hir_binary_span_step",
                groups,
            );
        }
        Ok(())
    }
}

fn pointer_jump_steps_for_items(items: u32) -> u32 {
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
