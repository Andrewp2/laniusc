use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData},
    parser::{buffers::ParserBuffers, passes::hir::bounded_walk_step_capacity},
};

/// Bounded-walk pass that propagates match arm ranks through arm lists.
pub struct HirMatchArmRankStepPass {
    data: PassData,
}

pub(in crate::parser) const A_TO_B: &str = "hir_match_arm_rank_step.a_to_b";
pub(in crate::parser) const B_TO_A: &str = "hir_match_arm_rank_step.b_to_a";
pub(in crate::parser) const A_TO_B_FINAL: &str = "hir_match_arm_rank_step.a_to_b_final";
pub(in crate::parser) const FINALIZE: &str = "hir_match_arm_rank_step.finalize";

crate::gpu::passes_core::impl_static_shader_pass!(
    HirMatchArmRankStepPass,
    label: "hir_match_arm_rank_step",
    shader: "parser/hir/match/arm/rank_step"
);

impl HirMatchArmRankStepPass {
    /// Records all match arm rank propagation steps with indirect dispatch sizing.
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
        let (
            arm_owner_in,
            arm_link_in,
            arm_rank_in,
            payload_owner_in,
            payload_link_in,
            payload_rank_in,
            pattern_parent_in,
            arm_owner_out,
            arm_link_out,
            arm_rank_out,
            payload_owner_out,
            payload_link_out,
            payload_rank_out,
            pattern_parent_out,
        ) = if read_from_a {
            (
                &buffers.hir_match_arm_owner_a,
                &buffers.hir_match_arm_link_a,
                &buffers.hir_match_arm_rank_a,
                &buffers.hir_match_payload_owner_a,
                &buffers.hir_match_payload_link_a,
                &buffers.hir_match_payload_rank_a,
                &buffers.hir_match_pattern_parent,
                &buffers.hir_match_arm_owner_b,
                &buffers.hir_match_arm_link_b,
                &buffers.hir_match_arm_rank_b,
                &buffers.hir_match_payload_owner_b,
                &buffers.hir_match_payload_link_b,
                &buffers.hir_match_payload_rank_b,
                &buffers.hir_match_pattern_parent_b,
            )
        } else {
            (
                &buffers.hir_match_arm_owner_b,
                &buffers.hir_match_arm_link_b,
                &buffers.hir_match_arm_rank_b,
                &buffers.hir_match_payload_owner_b,
                &buffers.hir_match_payload_link_b,
                &buffers.hir_match_payload_rank_b,
                &buffers.hir_match_pattern_parent_b,
                &buffers.hir_match_arm_owner_a,
                &buffers.hir_match_arm_link_a,
                &buffers.hir_match_arm_rank_a,
                &buffers.hir_match_payload_owner_a,
                &buffers.hir_match_payload_link_a,
                &buffers.hir_match_payload_rank_a,
                &buffers.hir_match_pattern_parent,
            )
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gHirMatch".into(),
                buffers.hir_enum_match_fields_params.as_entire_binding(),
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
                "token_feature_flags".into(),
                buffers.token_feature_flags.as_entire_binding(),
            ),
            (
                "hir_match_rank_node".into(),
                buffers.hir_match_rank_node.as_entire_binding(),
            ),
            (
                "hir_match_rank_count".into(),
                buffers.hir_match_rank_count.as_entire_binding(),
            ),
            (
                "hir_match_arm_owner_in".into(),
                arm_owner_in.as_entire_binding(),
            ),
            (
                "hir_match_arm_link_in".into(),
                arm_link_in.as_entire_binding(),
            ),
            (
                "hir_match_arm_rank_in".into(),
                arm_rank_in.as_entire_binding(),
            ),
            (
                "hir_match_payload_owner_in".into(),
                payload_owner_in.as_entire_binding(),
            ),
            (
                "hir_match_payload_link_in".into(),
                payload_link_in.as_entire_binding(),
            ),
            (
                "hir_match_payload_rank_in".into(),
                payload_rank_in.as_entire_binding(),
            ),
            (
                "hir_match_pattern_parent_in".into(),
                pattern_parent_in.as_entire_binding(),
            ),
            (
                "hir_match_arm_owner_out".into(),
                arm_owner_out.as_entire_binding(),
            ),
            (
                "hir_match_arm_link_out".into(),
                arm_link_out.as_entire_binding(),
            ),
            (
                "hir_match_arm_rank_out".into(),
                arm_rank_out.as_entire_binding(),
            ),
            (
                "hir_match_payload_owner_out".into(),
                payload_owner_out.as_entire_binding(),
            ),
            (
                "hir_match_payload_link_out".into(),
                payload_link_out.as_entire_binding(),
            ),
            (
                "hir_match_payload_rank_out".into(),
                payload_rank_out.as_entire_binding(),
            ),
            (
                "hir_match_pattern_parent_out".into(),
                pattern_parent_out.as_entire_binding(),
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
            .expect("match-arm rank step must have one reflected bind group");
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
