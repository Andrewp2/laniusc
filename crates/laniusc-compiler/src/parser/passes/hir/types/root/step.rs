use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData},
    parser::{buffers::ParserBuffers, passes::hir::list::rank::step::list_rank_step_capacity},
};

/// Bounded-walks direct type-parent links into topmost root ownership over
/// the compacted type rows.
pub struct HirTypeRootOwnerStepPass {
    data: PassData,
}

pub(in crate::parser) const A_TO_B: &str = "hir_type_root_owner_step.a_to_b";
pub(in crate::parser) const B_TO_A: &str = "hir_type_root_owner_step.b_to_a";

crate::gpu::passes_core::impl_static_shader_pass!(
    HirTypeRootOwnerStepPass,
    label: "hir_type_root_owner_step",
    shader: "parser/hir/type/root/owner/step"
);

impl HirTypeRootOwnerStepPass {
    /// Records an even number of steps, so the result ends in the A buffers.
    pub fn record_steps_indirect(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &ParserBuffers,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let steps = list_rank_step_capacity(b.tree_capacity);
        for step in 0..steps {
            self.record_step(device, encoder, b, step, dispatch_args, cache)?;
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &ParserBuffers,
        step: u32,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let read_a = step % 2 == 0;
        let (link_in, owner_in, link_out, owner_out) = if read_a {
            (
                &b.hir_type_arg_link_a,
                &b.hir_type_root_owner,
                &b.hir_type_arg_link_b,
                &b.hir_type_arg_owner_b,
            )
        } else {
            (
                &b.hir_type_arg_link_b,
                &b.hir_type_arg_owner_b,
                &b.hir_type_arg_link_a,
                &b.hir_type_root_owner,
            )
        };
        let resources = HashMap::from([
            (
                "gHirType".into(),
                b.hir_type_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_list_rank_node".into(),
                b.hir_list_rank_node.as_entire_binding(),
            ),
            (
                "hir_list_rank_count".into(),
                b.hir_list_rank_count.as_entire_binding(),
            ),
            ("hir_type_root_link_in".into(), link_in.as_entire_binding()),
            (
                "hir_type_root_owner_in".into(),
                owner_in.as_entire_binding(),
            ),
            (
                "hir_type_root_link_out".into(),
                link_out.as_entire_binding(),
            ),
            (
                "hir_type_root_owner_out".into(),
                owner_out.as_entire_binding(),
            ),
        ]);
        let label = if read_a { A_TO_B } else { B_TO_A };
        let invocation = format!("{label}.{step}");
        let group = cache
            .reflected_for_graph_invocation(
                device,
                &invocation,
                label,
                &self.data,
                b,
                &resources,
                Some(dispatch_args),
            )?
            .into_iter()
            .next()
            .expect("type-root step must have one reflected bind group");
        crate::gpu::passes_core::record_or_defer_compute_indirect(
            encoder,
            &self.data,
            group.as_ref(),
            label,
            dispatch_args,
        );
        Ok(())
    }

    pub(in crate::parser) fn graph_pass(&self) -> &PassData {
        &self.data
    }
}
