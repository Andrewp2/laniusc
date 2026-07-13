use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{PassData, bind_group},
    parser::{
        buffers::ParserBuffers,
        passes::hir::semantic::parent::step::pointer_jump_steps_after_local_span,
    },
};

/// Pointer-jump pass that computes dense semantic-node depth.
pub struct HirSemanticDepthStepPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticDepthStepPass,
    label: "hir_semantic_depth_step",
    shader: "parser/hir/semantic/depth/step"
);

impl HirSemanticDepthStepPass {
    /// Records all semantic depth propagation steps with indirect dispatch sizing.
    pub fn record_steps_indirect(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<()> {
        let steps = pointer_jump_steps_after_local_span(buffers.tree_capacity);
        for step in 0..steps {
            self.record_step(device, encoder, buffers, step % 2 == 0, dispatch_args)?;
        }

        if steps % 2 == 1 {
            crate::gpu::passes_core::flush_deferred_compute(encoder);
            let bytes = u64::from(buffers.tree_capacity) * 4;
            for (src, dst) in [
                (
                    &buffers.hir_semantic_depth_link_b,
                    &buffers.hir_semantic_depth_link_a,
                ),
                (
                    &buffers.hir_semantic_depth_value_b,
                    &buffers.hir_semantic_depth_value_a,
                ),
            ] {
                encoder.copy_buffer_to_buffer(&src.buffer, 0, &dst.buffer, 0, bytes);
            }
        }

        crate::gpu::passes_core::flush_deferred_compute(encoder);
        encoder.copy_buffer_to_buffer(
            &buffers.hir_semantic_depth_value_a.buffer,
            0,
            &buffers.hir_semantic_depth.buffer,
            0,
            u64::from(buffers.tree_capacity) * 4,
        );

        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        read_from_a: bool,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<()> {
        let (link_in, value_in, link_out, value_out) = if read_from_a {
            (
                &buffers.hir_semantic_depth_link_a,
                &buffers.hir_semantic_depth_value_a,
                &buffers.hir_semantic_depth_link_b,
                &buffers.hir_semantic_depth_value_b,
            )
        } else {
            (
                &buffers.hir_semantic_depth_link_b,
                &buffers.hir_semantic_depth_value_b,
                &buffers.hir_semantic_depth_link_a,
                &buffers.hir_semantic_depth_value_a,
            )
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gHirSemantic".into(),
                buffers.hir_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if buffers.tree_count_uses_status {
                    buffers.partial_parse_status.as_entire_binding()
                } else {
                    buffers.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_semantic_count".into(),
                buffers.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_semantic_depth_link_in".into(),
                link_in.as_entire_binding(),
            ),
            (
                "hir_semantic_depth_value_in".into(),
                value_in.as_entire_binding(),
            ),
            (
                "hir_semantic_depth_link_out".into(),
                link_out.as_entire_binding(),
            ),
            (
                "hir_semantic_depth_value_out".into(),
                value_out.as_entire_binding(),
            ),
        ]);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_semantic_depth_step"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;

        crate::gpu::passes_core::record_or_defer_compute_indirect(
            encoder,
            &self.data,
            &bind_group,
            "hir_semantic_depth_step",
            dispatch_args,
        );
        Ok(())
    }
}
