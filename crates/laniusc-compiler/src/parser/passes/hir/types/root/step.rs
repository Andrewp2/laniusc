use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData},
    parser::{buffers::ParserBuffers, passes::hir::bounded_walk_step_capacity},
};

/// Bounded-walks direct type-parent links into topmost root ownership.
pub struct HirTypeRootOwnerStepPass {
    data: PassData,
}

pub(in crate::parser) const A_TO_B: &str = "hir_type_root_owner_step.a_to_b";
pub(in crate::parser) const B_TO_A: &str = "hir_type_root_owner_step.b_to_a";
pub(in crate::parser) const A_TO_B_FINAL: &str = "hir_type_root_owner_step.a_to_b_final";
pub(in crate::parser) const FINALIZE: &str = "hir_type_root_owner_step.finalize";

crate::gpu::passes_core::impl_static_shader_pass!(
    HirTypeRootOwnerStepPass,
    label: "hir_type_root_owner_step",
    shader: "parser/hir/type/root/owner/step"
);

impl HirTypeRootOwnerStepPass {
    pub fn record_steps_indirect(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &ParserBuffers,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let steps = bounded_walk_step_capacity(b.tree_capacity);
        for step in 0..steps {
            self.record_step(
                device,
                encoder,
                b,
                step,
                step % 2 == 0,
                step + 1 == steps && steps % 2 == 1,
                dispatch_args,
                cache,
            )?;
        }
        if steps % 2 == 1 {
            b.record_finalizer(FINALIZE, encoder)?;
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &ParserBuffers,
        step: u32,
        read_a: bool,
        final_unpaired_step: bool,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
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
        let label = if final_unpaired_step {
            A_TO_B_FINAL
        } else if read_a {
            A_TO_B
        } else {
            B_TO_A
        };
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
