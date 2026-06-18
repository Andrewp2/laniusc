use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    parser::buffers::ParserBuffers,
};

/// Pointer-jump pass that propagates match arm ranks through arm lists.
pub struct HirMatchArmRankStepPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirMatchArmRankStepPass,
    label: "hir_match_arm_rank_step",
    shader: "parser/hir/match/arm/rank_step"
);

impl HirMatchArmRankStepPass {
    /// Records all match arm rank propagation steps with direct dispatch sizing.
    pub fn record_steps(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        self.record_steps_inner(device, encoder, buffers, None)
    }

    /// Records all match arm rank propagation steps with indirect dispatch sizing.
    pub fn record_steps_indirect(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<()> {
        self.record_steps_inner(device, encoder, buffers, Some(dispatch_args))
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
            let bytes = u64::from(buffers.tree_capacity) * 4;
            for (src, dst) in [
                (
                    &buffers.hir_match_arm_owner_b,
                    &buffers.hir_match_arm_owner_a,
                ),
                (&buffers.hir_match_arm_link_b, &buffers.hir_match_arm_link_a),
                (&buffers.hir_match_arm_rank_b, &buffers.hir_match_arm_rank_a),
                (
                    &buffers.hir_match_payload_owner_b,
                    &buffers.hir_match_payload_owner_a,
                ),
                (
                    &buffers.hir_match_payload_link_b,
                    &buffers.hir_match_payload_link_a,
                ),
                (
                    &buffers.hir_match_payload_rank_b,
                    &buffers.hir_match_payload_rank_a,
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
        dispatch_args: Option<&wgpu::Buffer>,
    ) -> Result<()> {
        let (
            arm_owner_in,
            arm_link_in,
            arm_rank_in,
            payload_owner_in,
            payload_link_in,
            payload_rank_in,
            arm_owner_out,
            arm_link_out,
            arm_rank_out,
            payload_owner_out,
            payload_link_out,
            payload_rank_out,
        ) = if read_from_a {
            (
                &buffers.hir_match_arm_owner_a,
                &buffers.hir_match_arm_link_a,
                &buffers.hir_match_arm_rank_a,
                &buffers.hir_match_payload_owner_a,
                &buffers.hir_match_payload_link_a,
                &buffers.hir_match_payload_rank_a,
                &buffers.hir_match_arm_owner_b,
                &buffers.hir_match_arm_link_b,
                &buffers.hir_match_arm_rank_b,
                &buffers.hir_match_payload_owner_b,
                &buffers.hir_match_payload_link_b,
                &buffers.hir_match_payload_rank_b,
            )
        } else {
            (
                &buffers.hir_match_arm_owner_b,
                &buffers.hir_match_arm_link_b,
                &buffers.hir_match_arm_rank_b,
                &buffers.hir_match_payload_owner_b,
                &buffers.hir_match_payload_link_b,
                &buffers.hir_match_payload_rank_b,
                &buffers.hir_match_arm_owner_a,
                &buffers.hir_match_arm_link_a,
                &buffers.hir_match_arm_rank_a,
                &buffers.hir_match_payload_owner_a,
                &buffers.hir_match_payload_link_a,
                &buffers.hir_match_payload_rank_a,
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
                    buffers.projected_status.as_entire_binding()
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
        ]);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_match_arm_rank_step"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;

        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("hir_match_arm_rank_step"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.data.pipeline);
        pass.set_bind_group(0, Some(&bind_group), &[]);
        if let Some(dispatch_args) = dispatch_args {
            pass.dispatch_workgroups_indirect(dispatch_args, 0);
        } else {
            let [tgsx, tgsy, _] = self.data.thread_group_size;
            let (gx, gy, gz) = plan_workgroups(
                DispatchDim::D1,
                InputElements::Elements1D(buffers.tree_capacity),
                [tgsx, tgsy, 1],
            )?;
            pass.dispatch_workgroups(gx, gy, gz);
        }
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
