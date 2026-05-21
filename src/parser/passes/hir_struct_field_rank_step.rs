use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    parser::buffers::ParserBuffers,
};

pub struct HirStructFieldRankStepPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirStructFieldRankStepPass,
    label: "hir_struct_field_rank_step",
    shader: "hir_struct_field_rank_step"
);

impl HirStructFieldRankStepPass {
    pub fn record_steps(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        self.record_steps_inner(device, encoder, buffers, None)
    }

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
                    &buffers.hir_struct_field_owner_b,
                    &buffers.hir_struct_field_owner_a,
                ),
                (
                    &buffers.hir_struct_field_link_b,
                    &buffers.hir_struct_field_link_a,
                ),
                (
                    &buffers.hir_struct_field_rank_b,
                    &buffers.hir_struct_field_rank_a,
                ),
                (
                    &buffers.hir_struct_lit_field_owner_b,
                    &buffers.hir_struct_lit_field_owner_a,
                ),
                (
                    &buffers.hir_struct_lit_field_link_b,
                    &buffers.hir_struct_lit_field_link_a,
                ),
                (
                    &buffers.hir_struct_lit_field_rank_b,
                    &buffers.hir_struct_lit_field_rank_a,
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
            field_owner_in,
            field_link_in,
            field_rank_in,
            lit_owner_in,
            lit_link_in,
            lit_rank_in,
            field_owner_out,
            field_link_out,
            field_rank_out,
            lit_owner_out,
            lit_link_out,
            lit_rank_out,
        ) = if read_from_a {
            (
                &buffers.hir_struct_field_owner_a,
                &buffers.hir_struct_field_link_a,
                &buffers.hir_struct_field_rank_a,
                &buffers.hir_struct_lit_field_owner_a,
                &buffers.hir_struct_lit_field_link_a,
                &buffers.hir_struct_lit_field_rank_a,
                &buffers.hir_struct_field_owner_b,
                &buffers.hir_struct_field_link_b,
                &buffers.hir_struct_field_rank_b,
                &buffers.hir_struct_lit_field_owner_b,
                &buffers.hir_struct_lit_field_link_b,
                &buffers.hir_struct_lit_field_rank_b,
            )
        } else {
            (
                &buffers.hir_struct_field_owner_b,
                &buffers.hir_struct_field_link_b,
                &buffers.hir_struct_field_rank_b,
                &buffers.hir_struct_lit_field_owner_b,
                &buffers.hir_struct_lit_field_link_b,
                &buffers.hir_struct_lit_field_rank_b,
                &buffers.hir_struct_field_owner_a,
                &buffers.hir_struct_field_link_a,
                &buffers.hir_struct_field_rank_a,
                &buffers.hir_struct_lit_field_owner_a,
                &buffers.hir_struct_lit_field_link_a,
                &buffers.hir_struct_lit_field_rank_a,
            )
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gHirStruct".into(),
                buffers.hir_struct_fields_params.as_entire_binding(),
            ),
            (
                "ll1_status".into(),
                if buffers.tree_count_uses_status && !buffers.tree_stream_uses_ll1 {
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
                "hir_struct_rank_node".into(),
                buffers.hir_struct_rank_node.as_entire_binding(),
            ),
            (
                "hir_struct_field_owner_in".into(),
                field_owner_in.as_entire_binding(),
            ),
            (
                "hir_struct_field_link_in".into(),
                field_link_in.as_entire_binding(),
            ),
            (
                "hir_struct_field_rank_in".into(),
                field_rank_in.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_owner_in".into(),
                lit_owner_in.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_link_in".into(),
                lit_link_in.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_rank_in".into(),
                lit_rank_in.as_entire_binding(),
            ),
            (
                "hir_struct_field_owner_out".into(),
                field_owner_out.as_entire_binding(),
            ),
            (
                "hir_struct_field_link_out".into(),
                field_link_out.as_entire_binding(),
            ),
            (
                "hir_struct_field_rank_out".into(),
                field_rank_out.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_owner_out".into(),
                lit_owner_out.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_link_out".into(),
                lit_link_out.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_rank_out".into(),
                lit_rank_out.as_entire_binding(),
            ),
        ]);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_struct_field_rank_step"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;

        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("hir_struct_field_rank_step"),
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
