use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData},
    parser::{buffers::ParserBuffers, passes::hir::bounded_walk_step_capacity},
};

/// Bounded-walk pass that propagates nearest type-alias owner records.
pub struct HirTypeAliasOwnerStepPass {
    data: PassData,
}

pub(in crate::parser) const A_TO_B: &str = "hir_type_alias_owner_step.a_to_b";
pub(in crate::parser) const B_TO_A: &str = "hir_type_alias_owner_step.b_to_a";
pub(in crate::parser) const A_TO_B_FINAL: &str = "hir_type_alias_owner_step.a_to_b_final";
pub(in crate::parser) const FINALIZE: &str = "hir_type_alias_owner_step.finalize";

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
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let steps = bounded_walk_step_capacity(buffers.tree_capacity);
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
            .expect("type-alias owner step must have one reflected bind group");

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
