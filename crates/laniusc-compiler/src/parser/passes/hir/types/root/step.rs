use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{PassData, bind_group},
    parser::buffers::ParserBuffers,
};

/// Pointer-doubles direct type-parent links into topmost root ownership.
pub struct HirTypeRootOwnerStepPass {
    data: PassData,
}

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
        dispatch_schedule: &wgpu::Buffer,
    ) -> Result<()> {
        let steps = pointer_jump_steps(b.tree_capacity);
        for step in 0..steps {
            self.record_step(
                device,
                encoder,
                b,
                step % 2 == 0,
                dispatch_schedule,
                u64::from(step) * 3 * std::mem::size_of::<u32>() as u64,
            )?;
        }
        if steps % 2 == 1 {
            crate::gpu::passes_core::flush_deferred_compute(encoder);
            encoder.copy_buffer_to_buffer(
                &b.hir_type_arg_owner_b.buffer,
                0,
                &b.hir_type_root_owner.buffer,
                0,
                u64::from(b.tree_capacity) * 4,
            );
        }
        Ok(())
    }

    fn record_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &ParserBuffers,
        read_a: bool,
        dispatch_schedule: &wgpu::Buffer,
        dispatch_offset: u64,
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
        let group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_type_root_owner_step"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        crate::gpu::passes_core::record_or_defer_compute_indirect_offset(
            encoder,
            &self.data,
            &group,
            "hir_type_root_owner_step",
            dispatch_schedule,
            dispatch_offset,
        );
        Ok(())
    }
}

fn pointer_jump_steps(items: u32) -> u32 {
    let mut span = 1u32;
    let mut steps = 0u32;
    while span < items {
        span = span.saturating_mul(2);
        steps += 1;
    }
    steps
}
