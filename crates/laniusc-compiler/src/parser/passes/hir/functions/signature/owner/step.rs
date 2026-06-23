use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    parser::buffers::ParserBuffers,
};

/// Pointer-jump pass that propagates function signature owner rows.
pub struct HirFnSignatureOwnerStepPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirFnSignatureOwnerStepPass,
    label: "hir_fn_signature_owner_step",
    shader: "parser/hir/fn/signature/owner/step"
);

impl HirFnSignatureOwnerStepPass {
    /// Records signature-owner propagation steps with indirect dispatch.
    pub fn record_steps_indirect(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<()> {
        self.record_steps_inner(device, encoder, buffers, Some(dispatch_args))
    }

    /// Records signature-owner propagation steps with direct dispatch.
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
            let bytes = u64::from(buffers.tree_capacity) * 4;
            for (src, dst) in [
                (
                    &buffers.hir_fn_signature_owner_link_b,
                    &buffers.hir_fn_signature_owner_link_a,
                ),
                (
                    &buffers.hir_fn_signature_return_owner_b,
                    &buffers.hir_fn_signature_return_owner_a,
                ),
                (
                    &buffers.hir_fn_signature_function_owner_b,
                    &buffers.hir_fn_signature_function_owner_a,
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
            link_in,
            return_owner_in,
            function_owner_in,
            link_out,
            return_owner_out,
            function_owner_out,
        ) = if read_from_a {
            (
                &buffers.hir_fn_signature_owner_link_a,
                &buffers.hir_fn_signature_return_owner_a,
                &buffers.hir_fn_signature_function_owner_a,
                &buffers.hir_fn_signature_owner_link_b,
                &buffers.hir_fn_signature_return_owner_b,
                &buffers.hir_fn_signature_function_owner_b,
            )
        } else {
            (
                &buffers.hir_fn_signature_owner_link_b,
                &buffers.hir_fn_signature_return_owner_b,
                &buffers.hir_fn_signature_function_owner_b,
                &buffers.hir_fn_signature_owner_link_a,
                &buffers.hir_fn_signature_return_owner_a,
                &buffers.hir_fn_signature_function_owner_a,
            )
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gHirFnSignatureOwner".into(),
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
                "hir_fn_signature_owner_link_in".into(),
                link_in.as_entire_binding(),
            ),
            (
                "hir_fn_signature_return_owner_in".into(),
                return_owner_in.as_entire_binding(),
            ),
            (
                "hir_fn_signature_function_owner_in".into(),
                function_owner_in.as_entire_binding(),
            ),
            (
                "hir_fn_signature_owner_link_out".into(),
                link_out.as_entire_binding(),
            ),
            (
                "hir_fn_signature_return_owner_out".into(),
                return_owner_out.as_entire_binding(),
            ),
            (
                "hir_fn_signature_function_owner_out".into(),
                function_owner_out.as_entire_binding(),
            ),
        ]);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_fn_signature_owner_step"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;

        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("hir_fn_signature_owner_step"),
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
