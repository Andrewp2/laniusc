use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    parser::buffers::ParserBuffers,
};

/// Pointer-jump pass that assigns call-argument ordinals within each call.
pub struct HirCallArgOrdinalStepPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCallArgOrdinalStepPass,
    label: "hir_call_arg_ordinal_step",
    shader: "parser/hir/call/arg/ordinal/step"
);

impl HirCallArgOrdinalStepPass {
    /// Records all call-argument ordinal propagation steps with direct dispatch.
    pub fn record_steps(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        self.record_steps_inner(device, encoder, buffers, None)
    }

    /// Records all call-argument ordinal propagation steps with indirect dispatch.
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
            crate::gpu::passes_core::flush_deferred_compute(encoder);
            let bytes = u64::from(buffers.tree_capacity) * 4;
            encoder.copy_buffer_to_buffer(
                &buffers.hir_call_arg_owner_b.buffer,
                0,
                &buffers.hir_call_arg_owner_a.buffer,
                0,
                bytes,
            );
            encoder.copy_buffer_to_buffer(
                &buffers.hir_call_arg_link_b.buffer,
                0,
                &buffers.hir_call_arg_link_a.buffer,
                0,
                bytes,
            );
            encoder.copy_buffer_to_buffer(
                &buffers.hir_call_arg_rank_b.buffer,
                0,
                &buffers.hir_call_arg_rank_a.buffer,
                0,
                bytes,
            );
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
        let owner_in = if read_from_a {
            &buffers.hir_call_arg_owner_a
        } else {
            &buffers.hir_call_arg_owner_b
        };
        let link_in = if read_from_a {
            &buffers.hir_call_arg_link_a
        } else {
            &buffers.hir_call_arg_link_b
        };
        let rank_in = if read_from_a {
            &buffers.hir_call_arg_rank_a
        } else {
            &buffers.hir_call_arg_rank_b
        };
        let owner_out = if read_from_a {
            &buffers.hir_call_arg_owner_b
        } else {
            &buffers.hir_call_arg_owner_a
        };
        let link_out = if read_from_a {
            &buffers.hir_call_arg_link_b
        } else {
            &buffers.hir_call_arg_link_a
        };
        let rank_out = if read_from_a {
            &buffers.hir_call_arg_rank_b
        } else {
            &buffers.hir_call_arg_rank_a
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gHirCall".into(),
                buffers.hir_call_fields_params.as_entire_binding(),
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
                "hir_list_rank_node".into(),
                buffers.hir_list_rank_node.as_entire_binding(),
            ),
            (
                "hir_list_rank_count".into(),
                buffers.hir_list_rank_count.as_entire_binding(),
            ),
            ("hir_call_arg_owner_in".into(), owner_in.as_entire_binding()),
            ("hir_call_arg_link_in".into(), link_in.as_entire_binding()),
            ("hir_call_arg_rank_in".into(), rank_in.as_entire_binding()),
            (
                "hir_call_arg_owner_out".into(),
                owner_out.as_entire_binding(),
            ),
            ("hir_call_arg_link_out".into(), link_out.as_entire_binding()),
            ("hir_call_arg_rank_out".into(), rank_out.as_entire_binding()),
        ]);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_call_arg_ordinal_step"),
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
                "hir_call_arg_ordinal_step",
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
                "hir_call_arg_ordinal_step",
                groups,
            );
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
