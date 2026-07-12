use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::{
        buffers::uniform_from_val,
        passes_core::{PassData, bind_group},
    },
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct Params {
    n: u32,
    source_len: u32,
    pool_capacity: u32,
    uses_status_count: u32,
}
pub struct HirStringDecodePass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirStringDecodePass,label:"hir_string_decode",shader:"parser/hir/string/decode");
impl HirStringDecodePass {
    pub fn record_with_source(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &ParserBuffers,
        source_len: u32,
        source: &wgpu::Buffer,
    ) -> Result<()> {
        let params = uniform_from_val(
            device,
            "parser.hir_string_decode.params",
            &Params {
                n: b.tree_capacity,
                source_len,
                pool_capacity: b.source_capacity,
                uses_status_count: u32::from(b.tree_count_uses_status),
            },
        );
        let resources = HashMap::from([
            ("gHirString".into(), params.as_entire_binding()),
            ("source_bytes".into(), source.as_entire_binding()),
            (
                "hir_string_node".into(),
                b.hir_string_node.as_entire_binding(),
            ),
            (
                "hir_string_count".into(),
                b.hir_string_count.as_entire_binding(),
            ),
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
        let group = bind_group::create_bind_group_from_reflection(
            device,
            Some("parser_hir_string_decode"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;
        crate::gpu::passes_core::record_or_defer_compute_indirect(
            encoder,
            &self.data,
            &group,
            "parser_hir_string_decode",
            &b.hir_list_rank_dispatch_args.buffer,
        );
        Ok(())
    }
}
