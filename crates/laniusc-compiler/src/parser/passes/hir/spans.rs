use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for generic HIR span extraction.
pub struct Params {
    pub n: u32,
    pub uses_status_count: u32,
    pub token_capacity: u32,
}

/// Pass that records generic source spans for HIR nodes.
pub struct HirSpansPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSpansPass,
    label: "hir_spans",
    shader: "parser/hir/spans"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSpansPass {
    const NAME: &'static str = "hir_spans";
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
            ("gHir".into(), b.hir_span_params.as_entire_binding()),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("token_count".into(), b.token_count.as_entire_binding()),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("first_child".into(), b.first_child.as_entire_binding()),
            ("subtree_end".into(), b.subtree_end.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            (
                "hir_token_file_id".into(),
                b.hir_token_file_id.as_entire_binding(),
            ),
            (
                "source_file_token_end".into(),
                b.source_file_token_end.as_entire_binding(),
            ),
            (
                "hir_type_path_leaf_node".into(),
                b.hir_type_path_leaf_node.as_entire_binding(),
            ),
            (
                "brace_match_depth".into(),
                b.token_brace_match_depth.as_entire_binding(),
            ),
            (
                "brace_match_block_min".into(),
                b.token_brace_match_block_min.as_entire_binding(),
            ),
            (
                "brace_match_min_tree".into(),
                b.token_brace_match_min_tree.as_entire_binding(),
            ),
            ("hir_token_end".into(), b.hir_token_end.as_entire_binding()),
        ])
    }
}
