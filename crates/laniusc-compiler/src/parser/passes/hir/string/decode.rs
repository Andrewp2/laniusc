use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(crate) struct Params {
    pub(crate) n: u32,
    pub(crate) source_len: u32,
    pub(crate) pool_capacity: u32,
    pub(crate) uses_status_count: u32,
    pub(crate) token_capacity: u32,
    pub(crate) retain_debug_rows: u32,
}
pub struct HirStringDecodePass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirStringDecodePass,label:"hir_string_decode",shader:"parser/hir/string/decode");
impl HirStringDecodePass {
    pub(in crate::parser) fn graph_pass(&self) -> &PassData {
        &self.data
    }

    pub fn record_with_source(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        b: &ParserBuffers,
        source_len: u32,
        source: &wgpu::Buffer,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        crate::parser::buffers::write_uniform(
            queue,
            &b.hir_string_decode_params,
            &Params {
                n: b.tree_capacity,
                source_len,
                pool_capacity: b.source_capacity,
                uses_status_count: u32::from(b.tree_count_uses_status),
                token_capacity: b.token_input_capacity,
                retain_debug_rows: u32::from(b.retain_debug_hir_buffers),
            },
        );
        let resources = HashMap::from([
            (
                "gHirString".into(),
                b.hir_string_decode_params.as_entire_binding(),
            ),
            ("source_bytes".into(), source.as_entire_binding()),
            (
                "hir_string_node".into(),
                b.hir_string_node.as_entire_binding(),
            ),
            (
                "hir_string_count".into(),
                b.hir_string_count.as_entire_binding(),
            ),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            (
                "hir_expr_string_start".into(),
                b.hir_expr_string_start.as_entire_binding(),
            ),
            (
                "hir_expr_string_len".into(),
                b.hir_expr_string_len.as_entire_binding(),
            ),
            (
                "hir_string_data_offset".into(),
                b.hir_string_data_offset.as_entire_binding(),
            ),
            (
                "hir_string_decoded_len".into(),
                b.hir_string_decoded_len.as_entire_binding(),
            ),
            (
                "hir_string_data_words".into(),
                b.hir_string_data_words.as_entire_binding(),
            ),
        ]);
        let group = cache
            .reflected_for_graph_external_invocation(
                device,
                "parser_hir_string_decode",
                &self.data,
                b,
                &resources,
                Some(&b.hir_list_rank_dispatch_args),
                &[source],
            )?
            .into_iter()
            .next()
            .expect("string-decode pass must have one reflected bind group");
        crate::gpu::passes_core::record_or_defer_compute_indirect(
            encoder,
            &self.data,
            group.as_ref(),
            "parser_hir_string_decode",
            &b.hir_list_rank_dispatch_args,
        );
        Ok(())
    }
}
