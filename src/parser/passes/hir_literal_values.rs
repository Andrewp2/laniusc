use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::{
        buffers::uniform_from_val,
        passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    },
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct Params {
    pub n: u32,
    pub source_len: u32,
    pub uses_ll1: u32,
}

pub struct HirLiteralValuesPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirLiteralValuesPass,
    label: "hir_literal_values",
    shader: "hir_literal_values"
);

impl HirLiteralValuesPass {
    pub fn record_with_source(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        source_len: u32,
        token_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
    ) -> Result<()> {
        let params = uniform_from_val(
            device,
            "parser.hir_literal_values.params",
            &Params {
                n: buffers.tree_capacity,
                source_len,
                uses_ll1: u32::from(buffers.tree_count_uses_status),
            },
        );
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gHirLiteral".into(), params.as_entire_binding()),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("source_bytes".into(), source_buf.as_entire_binding()),
            (
                "ll1_status".into(),
                if buffers.tree_count_uses_status && !buffers.tree_stream_uses_ll1 {
                    buffers.projected_status.as_entire_binding()
                } else {
                    buffers.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_expr_form".into(),
                buffers.hir_expr_form.as_entire_binding(),
            ),
            (
                "hir_expr_value_token".into(),
                buffers.hir_expr_value_token.as_entire_binding(),
            ),
            (
                "hir_type_len_token".into(),
                buffers.hir_type_len_token.as_entire_binding(),
            ),
            (
                "hir_expr_int_value".into(),
                buffers.hir_expr_int_value.as_entire_binding(),
            ),
            (
                "hir_type_len_value".into(),
                buffers.hir_type_len_value.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("parser_hir_literal_values"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(buffers.tree_capacity),
            [tgsx, tgsy, 1],
        )?;
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("parser_hir_literal_values"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.data.pipeline);
        pass.set_bind_group(0, Some(&bind_group), &[]);
        pass.dispatch_workgroups(gx, gy, gz);
        Ok(())
    }
}
