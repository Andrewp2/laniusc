use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for range expression span extraction.
pub struct Params {
    pub n: u32,
    pub uses_status_count: u32,
}

/// Pass that records source spans for range expressions.
pub struct HirRangeSpansPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirRangeSpansPass,
    label: "hir_range_spans",
    shader: "parser/hir/range_spans"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirRangeSpansPass {
    const NAME: &'static str = "hir_range_spans";
    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self {
        Self { data }
    }

    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        b: &'a ParserBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            (
                "gHirExpr".into(),
                b.hir_expr_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_semantic_dense_node".into(),
                b.hir_semantic_dense_node.as_entire_binding(),
            ),
            (
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_expr_record".into(),
                b.hir_expr_record.as_entire_binding(),
            ),
            (
                "hir_expr_result_root_node".into(),
                b.hir_expr_result_root_node.as_entire_binding(),
            ),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            ("hir_token_end".into(), b.hir_token_end.as_entire_binding()),
        ])
    }
}
