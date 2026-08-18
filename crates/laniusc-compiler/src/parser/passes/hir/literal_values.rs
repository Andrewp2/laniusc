use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for literal value extraction.
pub(crate) struct Params {
    pub(crate) n: u32,
    pub(crate) source_len: u32,
    pub(crate) uses_status_count: u32,
    pub(crate) token_capacity: u32,
    pub(crate) retain_debug_rows: u32,
}

/// Pass that records literal token ranges and value-source references.
pub struct HirLiteralValuesPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirLiteralValuesPass,
    label: "hir_literal_values",
    shader: "parser/hir/literal_values"
);

impl HirLiteralValuesPass {
    pub(in crate::parser) fn graph_pass(&self) -> &PassData {
        &self.data
    }

    /// Records literal value extraction using the original source buffer.
    pub fn record_with_source(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
        source_len: u32,
        token_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        crate::parser::buffers::write_uniform(
            queue,
            &buffers.hir_literal_values_params,
            &Params {
                n: buffers.tree_capacity,
                source_len,
                uses_status_count: u32::from(buffers.tree_count_uses_status),
                token_capacity: buffers.token_input_capacity,
                retain_debug_rows: u32::from(buffers.retain_debug_hir_buffers),
            },
        );
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gHirLiteral".into(),
                buffers.hir_literal_values_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("source_bytes".into(), source_buf.as_entire_binding()),
            (
                "tree_count_status".into(),
                if buffers.tree_count_uses_status {
                    buffers.partial_parse_status.as_entire_binding()
                } else {
                    buffers.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_expr_record".into(),
                buffers.hir_expr_record.as_entire_binding(),
            ),
            (
                "hir_token_pos".into(),
                buffers.hir_token_pos.as_entire_binding(),
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
                "hir_expr_float_bits".into(),
                buffers.hir_expr_float_bits.as_entire_binding(),
            ),
            (
                "hir_expr_string_start".into(),
                buffers.hir_expr_string_start.as_entire_binding(),
            ),
            (
                "hir_expr_string_len".into(),
                buffers.hir_expr_string_len.as_entire_binding(),
            ),
            (
                "hir_type_len_value".into(),
                buffers.hir_type_len_value.as_entire_binding(),
            ),
        ]);
        let bind_group = cache
            .reflected_for_graph_external_invocation(
                device,
                "parser_hir_literal_values",
                &self.data,
                buffers,
                &resources,
                Some(dispatch_args),
                &[token_buf, source_buf],
            )?
            .into_iter()
            .next()
            .expect("literal-values pass must have one reflected bind group");
        crate::gpu::passes_core::record_or_defer_compute_indirect(
            encoder,
            &self.data,
            bind_group.as_ref(),
            "parser_hir_literal_values",
            dispatch_args,
        );
        Ok(())
    }
}
