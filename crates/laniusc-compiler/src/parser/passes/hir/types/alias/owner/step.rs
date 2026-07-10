use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{PassData, bind_group},
    parser::buffers::ParserBuffers,
};

/// Pointer-jump pass that propagates nearest type-alias owner records.
pub struct HirTypeAliasOwnerStepPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirTypeAliasOwnerStepPass,
    label: "hir_type_alias_owner_step",
    shader: "parser/hir/type/alias/owner/step"
);

impl HirTypeAliasOwnerStepPass {
    /// Records all type-alias owner propagation steps with indirect dispatch sizing.
    pub fn record_steps_indirect(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: &wgpu::Buffer,
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
                    &buffers.hir_type_alias_owner_link_b,
                    &buffers.hir_type_alias_owner_link_a,
                ),
                (
                    &buffers.hir_type_alias_owner_value_b,
                    &buffers.hir_type_alias_owner_value_a,
                ),
            ] {
                encoder.copy_buffer_to_buffer(&src.buffer, 0, &dst.buffer, 0, bytes);
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
        dispatch_args: &wgpu::Buffer,
    ) -> Result<()> {
        let (link_in, value_in, link_out, value_out) = if read_from_a {
            (
                &buffers.hir_type_alias_owner_link_a,
                &buffers.hir_type_alias_owner_value_a,
                &buffers.hir_type_alias_owner_link_b,
                &buffers.hir_type_alias_owner_value_b,
            )
        } else {
            (
                &buffers.hir_type_alias_owner_link_b,
                &buffers.hir_type_alias_owner_value_b,
                &buffers.hir_type_alias_owner_link_a,
                &buffers.hir_type_alias_owner_value_a,
            )
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gHirTypeAliasOwner".into(),
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
                "hir_type_alias_owner_link_in".into(),
                link_in.as_entire_binding(),
            ),
            (
                "hir_type_alias_owner_value_in".into(),
                value_in.as_entire_binding(),
            ),
            (
                "hir_type_alias_owner_link_out".into(),
                link_out.as_entire_binding(),
            ),
            (
                "hir_type_alias_owner_value_out".into(),
                value_out.as_entire_binding(),
            ),
        ]);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_type_alias_owner_step"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;

        crate::gpu::passes_core::record_or_defer_compute_indirect(
            encoder,
            &self.data,
            &bind_group,
            "hir_type_alias_owner_step",
            dispatch_args,
        );
        Ok(())
    }
}

fn pointer_jump_steps_for_items(items: u32) -> u32 {
    let mut span = 1u32;
    let mut steps = 0u32;
    let target = items.max(1);
    while span < target {
        span = span.saturating_mul(2);
        steps += 1;
    }
    steps
}
