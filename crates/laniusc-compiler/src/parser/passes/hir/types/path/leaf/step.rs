use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData},
    parser::{buffers::ParserBuffers, passes::hir::bounded_walk_step_capacity},
};

/// Bounded-walk pass that resolves the leaf node for each HIR type path.
pub struct HirTypePathLeafStepPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirTypePathLeafStepPass,
    label: "hir_type_path_leaf_step",
    shader: "parser/hir/type/path/leaf/step"
);

impl HirTypePathLeafStepPass {
    pub(in crate::parser) fn graph_pass(&self) -> &PassData {
        &self.data
    }

    /// Records all type-path leaf propagation steps with indirect dispatch sizing.
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
                dispatch_args,
                cache,
            )?;
        }

        if steps % 2 == 1 {
            buffers.record_finalizer(
                crate::parser::compiler_graph::HIR_TYPE_PATH_LEAF_FINALIZE,
                encoder,
            )?;
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
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let (link_in, value_in, link_out, value_out) = if read_from_a {
            (
                &buffers.hir_type_path_leaf_link_a,
                &buffers.hir_type_path_leaf_value_a,
                &buffers.hir_type_path_leaf_link_b,
                &buffers.hir_type_path_leaf_value_b,
            )
        } else {
            (
                &buffers.hir_type_path_leaf_link_b,
                &buffers.hir_type_path_leaf_value_b,
                &buffers.hir_type_path_leaf_link_a,
                &buffers.hir_type_path_leaf_value_a,
            )
        };

        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gHirType".into(),
                buffers.hir_type_fields_params.as_entire_binding(),
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
                "hir_type_path_leaf_link_in".into(),
                link_in.as_entire_binding(),
            ),
            (
                "hir_type_path_leaf_value_in".into(),
                value_in.as_entire_binding(),
            ),
            (
                "hir_type_path_leaf_link_out".into(),
                link_out.as_entire_binding(),
            ),
            (
                "hir_type_path_leaf_value_out".into(),
                value_out.as_entire_binding(),
            ),
        ]);

        let operation = crate::parser::compiler_graph::HIR_TYPE_PATH_LEAF_STEPS
            .get(step as usize)
            .copied()
            .expect("type-path leaf walk exceeds registered graph step capacity");
        let bind_group = cache
            .reflected_for_graph_pass_data(
                device,
                operation,
                &self.data,
                buffers,
                &resources,
                Some(dispatch_args),
            )?
            .into_iter()
            .next()
            .expect("type-path leaf step must have one reflected bind group");
        crate::gpu::passes_core::record_or_defer_compute_indirect(
            encoder,
            &self.data,
            bind_group.as_ref(),
            operation,
            dispatch_args,
        );
        Ok(())
    }
}
