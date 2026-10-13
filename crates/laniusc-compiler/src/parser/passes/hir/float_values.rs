use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData},
    parser::buffers::ParserBuffers,
};

use super::literal_values::Params;

/// Exact floating candidates with a bounded storage workspace.
pub struct HirFloatValuesPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirFloatValuesPass,
    label: "hir_float_values",
    shader: "parser/hir/float_values"
);

impl HirFloatValuesPass {
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
        source_len: u32,
        token_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        if buffers.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_FLOAT_LITERALS == 0 {
            return Ok(());
        }
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
            ("hir_expr_float_bits".into(), buffers.hir_expr_float_bits.as_entire_binding()),
            ("hir_float_workspace".into(), buffers.hir_float_workspace.as_entire_binding()),
        ]);
        let bind_group = cache
            .reflected_for_graph_external_invocation(
                device,
                "parser_hir_float_values",
                &self.data,
                buffers,
                &resources,
                None,
                &[token_buf, source_buf],
            )?
            .into_iter()
            .next()
            .expect("literal-values pass must have one reflected bind group");
        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder,
            &self.data,
            bind_group.as_ref(),
            "parser_hir_float_values",
            (8, 1, 1),
        );
        Ok(())
    }
}
